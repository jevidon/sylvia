import CryptoKit
import Foundation
import Synchronization
import Testing
import SylviaBackgroundTransfer
import SylviaTransferClient
import SylviaTransferCore
@testable import G02TransferHarness

/// Wiring for the hosted simulator tests run by Spikes/G02-Transfer/Scripts/simulator-background-run.sh.
///
/// The script starts `sylvia-test-source` processes on the host and passes, through xcodebuild's
/// TEST_RUNNER_ prefix, for each source NAME (MAIN, FAULTY, SLOW):
///
///   G02_<NAME>_READY   JSON written by the source: source_id, fingerprint, port, endpoints, roots
///   G02_<NAME>_CODES   file of single-use pairing codes, one per line (mode 0600; never logged)
///
/// plus G02_EVIDENCE_DIR (where each test writes its log), G02_LAN_IP, G02_LOCAL_HOSTNAME,
/// G02_TAILSCALE_IP, G02_MAGICDNS and G02_CLEARTEXT (JSON: host -> port of plain HTTP servers).
/// The simulator shares the Mac's file system and network stack, so host paths and host loopback work.
enum SimEnvironment {
    static let values = ProcessInfo.processInfo.environment

    struct SourceInfo: Decodable, Sendable {
        struct Endpoint: Decodable, Sendable {
            var host: String
            var port: Int
        }
        var source_id: String
        var fingerprint: String
        var port: Int
        var endpoints: [Endpoint]
        var roots: [String]
    }

    static var isConfigured: Bool { values["G02_MAIN_READY"] != nil }

    static func source(_ name: String) throws -> SourceInfo {
        let path = try #require(values["G02_\(name)_READY"], "G02_\(name)_READY not set")
        return try JSONDecoder().decode(SourceInfo.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    }

    static func codesFile(_ name: String) throws -> String { try #require(values["G02_\(name)_CODES"]) }

    static var evidenceDirectory: URL? { values["G02_EVIDENCE_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) } }
}

/// Hands out each single-use pairing code once.
actor CodeBook {
    static let shared = CodeBook()
    private var used: [String: Int] = [:]

    func next(_ source: String) throws -> PairingPayload {
        let file = try SimEnvironment.codesFile(source)
        let lines = try String(contentsOfFile: file, encoding: .utf8).split(separator: "\n").map(String.init)
        let index = used[file, default: 0]
        guard index < lines.count else { throw CodeBookError.exhausted(source) }
        used[file] = index + 1
        return try PairingPayload.decode(lines[index], now: Date())
    }

    enum CodeBookError: Error { case exhausted(String) }
}

/// A background coordinator with its own session identifier, store and Keychain service, so tests do not
/// share state with each other or with the harness app's own coordinator.
struct TestClient {
    let coordinator: BackgroundTransferCoordinator
    let credentials: KeychainCredentialStore
    let root: URL
    let identifier: String

    static func make(_ tag: String, root: URL? = nil, identifier: String? = nil, options: BackgroundTransferCoordinator.Options = .init()) throws -> TestClient {
        let unique = UUID().uuidString.lowercased()
        let root = root ?? FileManager.default.temporaryDirectory.appendingPathComponent("g02-bg-\(tag)-\(unique)")
        let identifier = identifier ?? "com.jevidon.sylvia.spike.transfer.test.\(tag).\(unique)"
        let credentials = KeychainCredentialStore(service: "com.jevidon.sylvia.spike.transfer-bgtest.\(tag)")
        let coordinator = try BackgroundTransferCoordinator(
            kind: .background(identifier: identifier), root: root, credentials: credentials, options: options,
            appState: { TestClient.applicationState() })
        return TestClient(coordinator: coordinator, credentials: credentials, root: root, identifier: identifier)
    }

    /// The host app's state as its tracker records it (foreground while hosted tests run).
    static func applicationState() -> String { TransferRuntime.shared.appState.current }

    /// Pairs with the named source (the script's source approves automatically) and stores the token.
    func pair(_ source: String, deviceName: String) async throws -> (PairedSource, token: String) {
        let payload = try await CodeBook.shared.next(source)
        let (paired, token) = try await SourceClient.pair(payload: payload, deviceID: CanonicalID.make(), deviceName: deviceName)
        try credentials.saveToken(token, sourceID: paired.sourceID)
        try coordinator.sources.upsert(paired)
        return (paired, token)
    }

    func itemID(_ sourceID: String, titled title: String) async throws -> String {
        let client = try #require(coordinator.client(sourceID: sourceID))
        let items = try await client.catalog().items
        return try #require(items.first { $0.title == title }?.itemID, "no item \(title)")
    }

    @discardableResult
    func wait(_ jobID: String, seconds: Double = 240, until predicate: (BackgroundTransferCoordinator.JobView) -> Bool) async throws
        -> BackgroundTransferCoordinator.JobView
    {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if let view = coordinator.job(jobID), predicate(view) { return view }
            try await Task.sleep(for: .milliseconds(100))
        }
        let view = try #require(coordinator.job(jobID))
        Issue.record("timed out: job \(view.job.state) \(String(describing: view.job.pauseReason)), \(view.verifiedParts)/\(view.totalParts) parts")
        return view
    }

    func importedFile(_ version: String) throws -> URL {
        let record = try #require(coordinator.importer.record(itemVersionID: version))
        #expect(record.completions == 1)
        let asset = try #require(record.assets.first)
        return coordinator.importer.destination(importID: record.importID, assetID: asset.assetID)
    }

    func cleanUp() {
        coordinator.invalidate()
        for source in coordinator.sources.all { try? credentials.deleteToken(sourceID: source.sourceID) }
    }

    /// Writes the evidence log: environment, notes and every coordinator event (IDs, counts, addresses only).
    func writeEvidence(_ name: String, notes: [String]) {
        guard let directory = SimEnvironment.evidenceDirectory else { return }
        var lines = [
            "environment: simulator (\(ProcessInfo.processInfo.operatingSystemVersionString)), hosted test in G02TransferHarness;",
            "  client: SylviaBackgroundTransfer with URLSessionConfiguration.background(\"\(identifier.replacingOccurrences(of: #"\.[0-9a-f-]{36}$"#, with: ".<uuid>", options: .regularExpression))\")",
            "  source: sylvia-test-source on the host (see the run log for its options)",
        ]
        lines += notes
        lines += coordinator.log.allEntries().map { entry in
            "\(entry.time) \(entry.event) " + entry.fields.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data((lines.joined(separator: "\n") + "\n").utf8).write(to: directory.appendingPathComponent("\(name).log"))
    }
}

/// SHA-256 of a file, streamed.
func fileSHA256(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
    return Hex.encode(hasher.finalize())
}
