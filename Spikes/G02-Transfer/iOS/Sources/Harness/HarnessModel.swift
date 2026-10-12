import Foundation
import Network
import Observation
import Synchronization
import SylviaBackgroundTransfer
import SylviaTransferClient
import SylviaTransferCore
import UIKit

/// State behind the harness screens. Polls the coordinator twice a second; every action goes through
/// `TransferRuntime` and the shared TransferKit code the tests exercise.
@MainActor
@Observable
final class HarnessModel {
    // Pairing
    var codeText = ""
    var pendingPayload: PairingPayload?
    var pairingStatus = ""
    var pairingInProgress = false
    var pairingOverrideHost = ""
    var pairingOverridePort = ""

    // Sources, catalog, jobs
    var sources: [PairedSource] = []
    var catalog: [String: [CatalogItem]] = [:]
    var inbox: [String: [InboxEntry]] = [:]
    var catalogStatus = ""
    var jobs: [BackgroundTransferCoordinator.JobView] = []
    var reconciliation: BackgroundTransferCoordinator.ReconciliationSummary?
    var recentEvents: [TransferEventLog.Entry] = []

    // Manual address
    var manualHost = ""
    var manualPort = ""
    var manualStatus = ""

    // Bonjour
    var bonjour = BonjourBrowser()

    let runtime = TransferRuntime.shared
    private var pollTask: Task<Void, Never>?

    /// Set only by UI tests (launch environment): a file holding pairing codes, one per line.
    let testCodeFile = ProcessInfo.processInfo.environment["G02_PAIRING_CODE_FILE"]

    init() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func refresh() {
        sources = runtime.coordinator.sources.all
        jobs = runtime.coordinator.jobViews()
        reconciliation = runtime.coordinator.lastReconciliation
        recentEvents = Array(runtime.coordinator.log.recentEntries.suffix(40).reversed())
    }

    // MARK: Pairing

    /// Paste or type the code, or open a `sylvia://pair/v1#...` link. Nothing is sent until the person
    /// has seen the fingerprint and taps Pair.
    func checkCode() {
        do {
            pendingPayload = try PairingPayload.decode(codeText.trimmingCharacters(in: .whitespacesAndNewlines), now: Date())
            pairingStatus = "Compare this fingerprint with the one the Mac shows, then pair."
        } catch {
            pendingPayload = nil
            pairingStatus = "This is not a valid Sylvia pairing code (\(error))."
        }
    }

    func receivePairingLink(_ url: URL) {
        guard url.scheme == "sylvia" else { return }
        codeText = url.absoluteString
        checkCode()
    }

    func useTestCode() {
        guard let testCodeFile, let text = try? String(contentsOfFile: testCodeFile, encoding: .utf8) else {
            pairingStatus = "No test code file."
            return
        }
        // G02_PAIRING_CODE_LINE (UI tests): which code of the file to use, 1-based; the first by default.
        let line = Int(ProcessInfo.processInfo.environment["G02_PAIRING_CODE_LINE"] ?? "") ?? 1
        let codes = text.split(separator: "\n").map(String.init)
        codeText = codes.indices.contains(line - 1) ? codes[line - 1] : ""
        checkCode()
    }

    /// Before pairing: connect to an address the person types instead of the code's addresses (the Mac
    /// moved, or the code lists an address this phone cannot reach). The pin and the secret are the code's:
    /// a different Mac at this address fails the pin check and receives nothing (device checklist step 3).
    func overridePendingAddress() {
        guard var payload = pendingPayload else { return }
        let host = pairingOverrideHost.trimmingCharacters(in: .whitespaces)
        guard HostValidation.isValid(host), let port = Int(pairingOverridePort), (1...65_535).contains(port) else {
            pairingStatus = "Enter a host name or IP address and a port."
            return
        }
        payload.endpoints = [PairingPayload.Endpoint(host: host, port: port)]
        pendingPayload = payload
        pairingStatus = "Pairing will connect only to \(payload.endpoints[0].urlHost):\(port). The fingerprint is still the code's."
    }

    func pair() async {
        guard let payload = pendingPayload else { return }
        pairingInProgress = true
        pairingStatus = "Pairing: waiting for approval on the Mac..."
        do {
            let paired = try await runtime.pair(payload: payload, deviceName: UIDevice.current.name)
            pairingStatus = "Paired with \(paired.sourceName). Token stored in the Keychain (after first unlock, this device only)."
        } catch {
            pairingStatus = error.description
        }
        // The invitation is single use; clear the temporary pairing state either way (plan 15.2).
        codeText = ""
        pendingPayload = nil
        pairingOverrideHost = ""
        pairingOverridePort = ""
        pairingInProgress = false
        refresh()
    }

    // MARK: Catalog and jobs

    func loadCatalog(_ source: PairedSource) async {
        guard let client = runtime.coordinator.client(sourceID: source.sourceID) else { return }
        do throws(ClientError) {
            catalog[source.sourceID] = try await client.catalog().items
            catalogStatus = ""
        } catch {
            catalogStatus = "Catalog: \(Self.describe(await runtime.coordinator.explain(error, sourceID: source.sourceID)))"
        }
    }

    /// Lists what the Mac queued for this phone; the Mac then shows those entries as observed by the phone.
    func checkInbox(_ source: PairedSource) async {
        do throws(ClientError) {
            inbox[source.sourceID] = try await runtime.coordinator.inbox(sourceID: source.sourceID)
            catalogStatus = inbox[source.sourceID]?.isEmpty == true ? "Inbox: nothing queued for this iPhone." : ""
        } catch {
            catalogStatus = "Inbox: \(Self.describe(error))"
        }
    }

    func download(_ item: CatalogItem, from source: PairedSource) async {
        await startJob(source: source, itemID: item.itemID, title: item.title, queueEntryID: nil)
    }

    func download(_ entry: InboxEntry, from source: PairedSource) async {
        await startJob(source: source, itemID: entry.itemID, title: entry.title, queueEntryID: entry.queueEntryID)
    }

    private func startJob(source: PairedSource, itemID: String, title: String, queueEntryID: String?) async {
        do throws(ClientError) {
            _ = try await runtime.coordinator.startJob(sourceID: source.sourceID, itemID: itemID, title: title, queueEntryID: queueEntryID)
            catalogStatus = ""
        } catch {
            catalogStatus = "Could not start: \(Self.describe(error))"
        }
        refresh()
    }

    /// A denied local network permission gets its Settings next step (plan 14.3, 15.5); other errors are shown raw
    /// (harness only: the product's wording is M1 UI work).
    static func describe(_ error: ClientError) -> String {
        error == .localNetworkDenied ? PauseReason.localNetworkDenied.nextStep : "\(error)"
    }

    // MARK: Addresses

    func addManualAddress(to source: PairedSource) async {
        let host = manualHost.trimmingCharacters(in: .whitespaces)
        guard HostValidation.isValid(host), let port = Int(manualPort), (1...65_535).contains(port) else {
            manualStatus = "Enter a host name or IP address and a port."
            return
        }
        await prefer(PairingPayload.Endpoint(host: host, port: port), for: source)
    }

    func prefer(_ endpoint: PairingPayload.Endpoint, for source: PairedSource) async {
        manualStatus = "Checking \(endpoint.urlHost):\(endpoint.port) against the paired fingerprint..."
        do throws(ClientError) {
            _ = try await runtime.coordinator.verifyAndPreferEndpoint(sourceID: source.sourceID, endpoint: endpoint)
            manualStatus = "Using \(endpoint.urlHost):\(endpoint.port): the Mac's key matches the paired fingerprint."
        } catch {
            manualStatus = "\(endpoint.urlHost):\(endpoint.port) did not work: \(Self.describe(error))"
        }
        refresh()
    }

    func useBonjourResult(_ result: BonjourBrowser.Found, for source: PairedSource) async {
        manualStatus = "Resolving \(result.name)..."
        guard let endpoint = await BonjourBrowser.resolveIPv4(result.endpoint) else {
            manualStatus = "Could not resolve \(result.name)."
            return
        }
        await prefer(endpoint, for: source)
    }
}

/// Browses `_sylvia-src._tcp` (NSBonjourServices) and resolves a result to an IPv4 address and port.
/// A Bonjour result is only a hint where to connect: the paired SPKI pin decides trust (plan 18.1).
@MainActor
@Observable
final class BonjourBrowser {
    struct Found: Identifiable, Hashable {
        var id: String { name }
        var name: String
        var sourceID: String?
        var endpoint: NWEndpoint
    }

    var found: [Found] = []
    var status = "Not browsing"
    private var browser: NWBrowser?

    func start() {
        browser?.cancel()
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_sylvia-src._tcp", domain: nil), using: .tcp)
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.status = "Browser: \(state)" }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let list = results.compactMap { result -> Found? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                var sourceID: String?
                if case .bonjour(let txt) = result.metadata { sourceID = txt["sid"] }
                return Found(name: name, sourceID: sourceID, endpoint: result.endpoint)
            }
            Task { @MainActor in self?.found = list.sorted { $0.name < $1.name } }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        status = "Not browsing"
    }

    /// Connects over TCP (no TLS, no data sent) only to learn the address the service resolves to.
    nonisolated static func resolveIPv4(_ endpoint: NWEndpoint, timeout: Duration = .seconds(10)) async -> PairingPayload.Endpoint? {
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let connection = NWConnection(to: endpoint, using: parameters)
        let result: PairingPayload.Endpoint? = await withCheckedContinuation { continuation in
            let once = OnceFlag()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    var resolved: PairingPayload.Endpoint?
                    if case .hostPort(let host, let port) = connection.currentPath?.remoteEndpoint {
                        let text: String
                        switch host {
                        // Drop an interface scope ("%en0"): the endpoint is a plain address for a URL.
                        case .ipv4(let address): text = String("\(address)".prefix { $0 != "%" })
                        case .ipv6(let address): text = String("\(address)".prefix { $0 != "%" })
                        case .name(let name, _): text = name
                        @unknown default: text = ""
                        }
                        resolved = PairingPayload.Endpoint(host: text, port: Int(port.rawValue))
                    }
                    if once.claim() { continuation.resume(returning: resolved) }
                case .failed, .cancelled:
                    if once.claim() { continuation.resume(returning: nil) }
                default: break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(Int(timeout.components.seconds))) {
                if once.claim() { continuation.resume(returning: nil) }
            }
        }
        connection.cancel()
        return result
    }
}

final class OnceFlag: Sendable {
    private let done = Synchronization.Mutex(false)
    func claim() -> Bool { done.withLock { was in defer { was = true }; return !was } }
}
