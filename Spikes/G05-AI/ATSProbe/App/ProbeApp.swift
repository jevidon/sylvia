import G05TestSupport
import Security
import SwiftUI
import SylviaAI
import UIKit

/// Test host for the G0.5 ATS, Keychain and suspension probes. It makes no network request on its own; the
/// suspension probe talks only to a fake server it starts inside the app on 127.0.0.1.
///
/// - Keychain (device checklist step 3): "Start Keychain lock probe" stores a non-secret marker item with the same
///   accessibility class as AI credentials, then reads it every 2 s for 60 s inside a background task and deletes
///   it. "Save marker only", "Read marker only" and "Delete marker" split that up for the reboot check, so an item
///   saved before a restart is read after it. Only status codes are logged (never the value), on screen and to
///   Documents/keychain-lock-probe.txt.
/// - Suspension (D4, simulator UI test and device checklist step 4): "Ask the in-app fake server" streams a long
///   answer from the fake server through the real generic adapter and AskCoordinator. When the scene leaves the
///   foreground the app stops every request with reason `.suspension`, inside a background task, as Sylvia must.
@main
struct ProbeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var suspension = StreamingSuspensionProbe()

    var body: some Scene {
        WindowGroup { ProbeView(suspension: suspension) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { suspension.appLeftForeground() }
            }
    }
}

struct ProbeView: View {
    @State private var probe = KeychainLockProbe()
    let suspension: StreamingSuspensionProbe

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("G0.5 probe · ATS variant: \(Bundle.main.object(forInfoDictionaryKey: "G05ATSVariant") as? String ?? "?")")
            HStack {
                Button("Start Keychain lock probe") { probe.start() }
                    .disabled(probe.running)
                    .accessibilityIdentifier("keychain.timed")
            }
            HStack {
                Button("Save marker only") { probe.saveOnly() }.accessibilityIdentifier("keychain.save")
                Button("Read marker only") { probe.readOnly() }.accessibilityIdentifier("keychain.read")
                Button("Delete marker") { probe.deleteMarker() }.accessibilityIdentifier("keychain.delete")
            }
            .disabled(probe.running)
            Divider()
            Button("Ask the in-app fake server") { suspension.start() }
                .disabled(suspension.started)
                .accessibilityIdentifier("suspension.start")
            Text(suspension.status).accessibilityIdentifier("suspension.status")
            Text("characters \(suspension.answerCharacters)").accessibilityIdentifier("suspension.chars")
            Text("requests \(suspension.serverRequests)").accessibilityIdentifier("suspension.requests")
            Text("question sent \(suspension.questionSent) times").accessibilityIdentifier("suspension.question")
            Text("stored \(suspension.storedState)").accessibilityIdentifier("suspension.stored")
            List(probe.lines + suspension.lines, id: \.self) { Text($0).font(.caption.monospaced()) }
        }
        .padding()
    }
}

@MainActor
@Observable
final class KeychainLockProbe {
    private(set) var lines: [String] = []
    private(set) var running = false
    private let store = KeychainCredentialStore(service: "com.jevidon.sylvia.spike.keychain-lock-probe")
    private let ref = CredentialRef(account: UUID(uuidString: "6B1F4C2E-0000-4000-8000-000000000001")!, origin: "https://keychain-lock-probe.invalid")
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid

    /// Ends the background task once, whether the probe finished or the system's expiration handler ran first.
    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func readStatus() -> String {
        do {
            _ = try store.secret(for: ref)
            return "readable"
        } catch CredentialStoreError.unavailableWhileLocked {
            return "unavailableWhileLocked (errSecInteractionNotAllowed)"
        } catch CredentialStoreError.notFound {
            return "notFound (no marker saved)"
        } catch {
            return "error \(error)"
        }
    }

    private func save() -> Bool {
        do {
            try store.save(Secret("not-a-secret-lock-probe-marker"), for: ref)
            log("saved marker; accessibility=\(store.storedAccessibility(for: ref) ?? "?")")
            return true
        } catch {
            log("save failed: \(error)")
            return false
        }
    }

    /// Reboot check, part 1: save the marker and leave it in place.
    func saveOnly() {
        lines.removeAll()
        if save() { log("marker kept for the reboot check; restart the phone, unlock it, then tap Read marker only") }
    }

    /// Reboot check, part 2 (and any time): one read of a marker saved earlier, without saving a new one.
    func readOnly() {
        log("read only: protectedDataAvailable=\(UIApplication.shared.isProtectedDataAvailable) read=\(readStatus())")
    }

    func deleteMarker() {
        do {
            try store.delete(ref)
            log("marker deleted")
        } catch {
            log("delete failed: \(error)")
        }
    }

    func start() {
        running = true
        lines.removeAll()
        guard save() else {
            running = false
            return
        }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "g05-keychain-lock-probe") { [weak self] in
            // UIKit calls the expiration handler on the main thread.
            MainActor.assumeIsolated {
                self?.log("background time expired; the system may suspend the probe now")
                self?.endBackgroundTask()
            }
        }
        Task {
            for second in stride(from: 0, through: 60, by: 2) {
                log("t=\(second)s protectedDataAvailable=\(UIApplication.shared.isProtectedDataAvailable) state=\(UIApplication.shared.applicationState.rawValue) read=\(readStatus())")
                try? await Task.sleep(for: .seconds(2))
            }
            try? store.delete(ref)
            log("done; marker deleted")
            running = false
            endBackgroundTask()
        }
    }

    func log(_ line: String) {
        let stamped = "\(RFC3339.string(Date())) \(line)"
        lines.append(stamped)
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("keychain-lock-probe.txt")
        let text = lines.joined(separator: "\n") + "\n"
        try? Data(text.utf8).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// Streams a long answer from a fake OpenAI-compatible server inside the app, through `HTTPTextGenerationProvider`
/// and `AskCoordinator`, and stops it when the app leaves the foreground (plan 14.4).
@MainActor
@Observable
final class StreamingSuspensionProbe {
    private(set) var started = false
    private(set) var status = "idle"
    private(set) var answerCharacters = 0
    private(set) var serverRequests = 0
    private(set) var questionSent = 0
    private(set) var storedState = "-"
    private(set) var lines: [String] = []

    static let question = "Probe question: what does Thoreau mean by living deliberately?"
    private var server: FakeHTTPServer?
    private var coordinator: AskCoordinator?
    private var directory: URL?
    private var requestID: UUID?

    func start() {
        started = true
        status = "starting"
        Task { await run() }
    }

    private func run() async {
        do {
            // About 60 s of answer, one word every 200 ms, so the stream is still running when the app leaves.
            let delta = #"data: {"choices":[{"index":0,"delta":{"content":"word "},"finish_reason":null}]}"# + "\n\n"
            let server = try await FakeHTTPServer { _ in .sse(Array(repeating: delta, count: 300) + ["data: [DONE]\n\n"], pauseMs: 200) }
            self.server = server
            let config = ProviderConfig(kind: .openAICompatibleChat, displayName: "In-app fake server", baseURL: server.url("/v1"),
                                        model: "probe-model", credential: nil, allowInsecureLocalHTTP: true)
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("suspension-probe-\(UUID().uuidString)")
            self.directory = directory
            let coordinator = AskCoordinator(store: try FileAskStore(directory: directory),
                                             providerFactory: { HTTPTextGenerationProvider(config: $0, credentials: InMemoryCredentialStore(),
                                                                                           transport: URLSessionTransport()) },
                                             connectivity: FakeConnectivity(online: true))
            self.coordinator = coordinator
            let pack = TestPacks.make(question: Self.question, config: config)
            requestID = pack.requestID
            _ = try await coordinator.createDraft(pack: pack, config: config)
            _ = try await coordinator.prepare(pack.requestID)
            // Tapping the button is the consent for this loopback destination (the probe's only destination).
            _ = try await coordinator.grantConsent(pack.requestID)
            log("consent granted for \(pack.endpoint.origin); sending")
            let poller = Task { await poll() }
            let record = try await coordinator.send(pack.requestID)
            poller.cancel()
            await show(record)
            log("send returned: state=\(record.state.rawValue) characters=\(record.answerText.count)")
        } catch {
            status = "probe error: \(error)"
            log(status)
        }
    }

    private func poll() async {
        while !Task.isCancelled {
            if let coordinator, let requestID, let record = try? await coordinator.record(requestID) { await show(record) }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    private func show(_ record: AskRecord) async {
        status = "\(record.state.rawValue) · \(record.statusPhrase)"
        answerCharacters = record.answerText.count
        if let server {
            serverRequests = server.requests.count
            questionSent = server.requests.map { $0.bodyText.components(separatedBy: Self.question).count - 1 }.reduce(0, +)
        }
        if let directory, let requestID, let stored = try? await FileAskStore(directory: directory).load(requestID) {
            storedState = "\(stored.state.rawValue) · \(stored.statusPhrase) · \(stored.answerText.count) characters"
        }
    }

    /// Called when the scene enters the background: stop every request, inside a background task so the
    /// interrupted record is durable before the process can be suspended.
    func appLeftForeground() {
        guard let coordinator else { return }
        stopTask = UIApplication.shared.beginBackgroundTask(withName: "g05-stop-ai-requests") { [weak self] in
            // UIKit calls the expiration handler on the main thread.
            MainActor.assumeIsolated { self?.endStopTask() }
        }
        Task {
            let stopped = await coordinator.stopAll(reason: .suspension)
            let idle = await coordinator.waitUntilIdle()
            log("left the foreground: stopped \(stopped.count) request(s); records written=\(idle)")
            endStopTask()
        }
    }

    private var stopTask = UIBackgroundTaskIdentifier.invalid

    private func endStopTask() {
        guard stopTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(stopTask)
        stopTask = .invalid
    }

    private func log(_ line: String) {
        lines.append("\(RFC3339.string(Date())) \(line)")
    }
}
