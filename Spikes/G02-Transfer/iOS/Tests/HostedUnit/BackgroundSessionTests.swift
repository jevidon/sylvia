import Foundation
import Network
import Synchronization
import Testing
import SylviaBackgroundTransfer
import SylviaTransferClient
import SylviaTransferCore
@testable import G02TransferHarness

/// G0.2 part 2 on the iOS simulator: background URLSession download tasks with the pinned task-level trust
/// answer, against `sylvia-test-source` processes on the host. Run by
/// Spikes/G02-Transfer/Scripts/simulator-background-run.sh; without its environment the suite is disabled
/// with that reason and the script fails if it did not run.
///
/// What this proves and what it cannot: the simulator runs the iOS networking stack, ATS, the Keychain and
/// a real background session (nsurlsessiond of the simulator runtime), but shares the Mac's network
/// interfaces, never locks, has no local-network permission prompt and is never suspended by the system
/// while a hosted test runs. Those cases are device checklist steps.
@Suite("Simulator: background session transfers (15.2 gate, 15.4, 15.5)", .serialized, .enabled(if: SimEnvironment.isConfigured, "run by simulator-background-run.sh"))
struct BackgroundSessionTests {
    static let protection = FileProtectionType.completeUntilFirstUserAuthentication

    func originalPath(_ info: SimEnvironment.SourceInfo, _ file: String) throws -> URL {
        URL(fileURLWithPath: try #require(info.roots.first)).appendingPathComponent(file)
    }

    @Test func fullTransferThroughTheBackgroundSessionWithThePinnedChallenge() async throws {
        let info = try SimEnvironment.source("MAIN")
        let client = try TestClient.make("full")
        defer { client.cleanUp() }
        await client.coordinator.start()
        let (paired, token) = try await client.pair("MAIN", deviceName: "Simulator background full")
        let itemID = try await client.itemID(paired.sourceID, titled: "meditations-librivox")
        let expected = try fileSHA256(try originalPath(info, "meditations-librivox.m4b"))
        let jobID = try await client.coordinator.startJob(sourceID: paired.sourceID, itemID: itemID, title: "meditations-librivox")
        let view = try await client.wait(jobID) { $0.job.state == .imported && $0.job.receiptsAcknowledged }
        #expect(view.job.state == .imported)
        #expect(try fileSHA256(try client.importedFile(view.job.itemVersionID)) == expected)

        let events = client.coordinator.log.allEntries()
        let requested = events.filter { $0.event == "part_requested" }
        let verified = events.filter { $0.event == "part_verified" }
        let challenges = events.filter { $0.event == "trust_challenge" }
        #expect(verified.count == 9 && requested.count == 9)
        #expect(!challenges.isEmpty)
        #expect(challenges.allSatisfy { $0.fields["level"] == "task" && $0.fields["result"] == "matched" })
        #expect(events.contains { $0.event == "task_metrics" && $0.fields["tls"] == "772" })  // TLS 1.3
        // The token never reaches the event log.
        #expect(!(try String(contentsOf: client.coordinator.log.url, encoding: .utf8)).contains(token))

        // Data protection class of the transfer store (plan 18.1). The code asks for "complete until first user
        // authentication"; the simulator has no data protection and reports no class, so this is recorded here and
        // verified on a device (checklist), never inferred.
        var protections: [String] = []
        for file in ["sources.json", "imports.json", "events.jsonl", "jobs/\(jobID)/job.json"] {
            let url = client.root.appendingPathComponent(file)
            let value = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.protectionKey] as? FileProtectionType
            protections.append("\(file): \(value?.rawValue ?? "none reported")")
            #expect(value == nil || value == Self.protection, "\(file): \(String(describing: value))")
        }
        client.writeEvidence("simulator/background-full-transfer", notes: [
            "item: LibriVox M4B, \(view.progress.totalBytes) bytes, \(verified.count) parts of 16 MiB; SHA-256 \(expected) matches the imported file",
            "trust challenges delivered to the app: \(challenges.count) (all task level, all pin matched); parts requested \(requested.count), verified \(verified.count)",
            "file protection: " + protections.joined(separator: "; "),
        ])
    }

    @Test func wrongPartDigestIsRefetchedAndEachNewConnectionIsPinned() async throws {
        let info = try SimEnvironment.source("FAULTY")
        let client = try TestClient.make("faulty")
        defer { client.cleanUp() }
        await client.coordinator.start()
        let (paired, _) = try await client.pair("FAULTY", deviceName: "Simulator background faulty")
        let itemID = try await client.itemID(paired.sourceID, titled: "sim-faulty")
        let expected = try fileSHA256(try originalPath(info, "sim-faulty.bin"))
        let jobID = try await client.coordinator.startJob(sourceID: paired.sourceID, itemID: itemID, title: "sim-faulty")
        let view = try await client.wait(jobID) { $0.job.state == .imported }
        #expect(try fileSHA256(try client.importedFile(view.job.itemVersionID)) == expected)
        let events = client.coordinator.log.allEntries()
        let failed = events.filter { $0.event == "part_failed" }
        #expect(failed.count == 1)
        #expect(failed.first?.fields["failure"] == "digestMismatch")
        #expect(failed.first?.fields["part"]?.hasSuffix(":1") == true)
        let requests = events.filter { $0.event == "part_requested" }
        #expect(requests.count == 5)  // 4 parts, part 1 twice
        let challenges = events.filter { $0.event == "trust_challenge" }
        let newConnections = events.filter { $0.event == "task_metrics" && $0.fields["reused_connection"] == "false" }
        #expect(challenges.allSatisfy { $0.fields["result"] == "matched" })
        #expect(challenges.count >= 1)
        client.writeEvidence("simulator/background-wrong-digest", notes: [
            "source: every response Connection: close; part 1's first response has one flipped byte",
            "result: part 1 failed once with digestMismatch and was fetched again; imported SHA-256 \(expected) matches",
            "requests \(requests.count), new TLS connections (task metrics) \(newConnections.count), trust challenges delivered \(challenges.count)",
        ])
    }

    @Test func sourceChangedMidTransferIsDetectedAndOnlyTheNewVersionIsImported() async throws {
        let info = try SimEnvironment.source("SLOW")
        let client = try TestClient.make("mutation")
        defer { client.cleanUp() }
        await client.coordinator.start()
        let (paired, _) = try await client.pair("SLOW", deviceName: "Simulator background mutation")
        let itemID = try await client.itemID(paired.sourceID, titled: "mutable")
        let file = try originalPath(info, "mutable.bin")
        let before = try fileSHA256(file)
        let jobID = try await client.coordinator.startJob(sourceID: paired.sourceID, itemID: itemID, title: "mutable")
        let firstVersion = try #require(client.coordinator.job(jobID)?.job.itemVersionID)
        _ = try await client.wait(jobID, seconds: 60) { $0.verifiedParts >= 1 }
        // The Mac user edits the original: the last 4 MiB part changes (written in place, as an editor might).
        let handle = try FileHandle(forUpdating: file)
        try handle.seek(toOffset: 22 * 1_048_576)
        try handle.write(contentsOf: Data(repeating: 0xA5, count: 4096))
        try handle.close()
        let after = try fileSHA256(file)
        #expect(after != before)
        let view = try await client.wait(jobID) { $0.job.state == .imported }
        #expect(view.job.itemVersionID != firstVersion)
        #expect(try fileSHA256(try client.importedFile(view.job.itemVersionID)) == after)
        let events = client.coordinator.log.allEntries()
        let change = try #require(events.first { $0.event == "version_changed" })
        #expect(Int(change.fields["kept_parts"] ?? "0") ?? 0 >= 1)
        #expect(events.contains { $0.event == "manifest_refresh_needed" })
        client.writeEvidence("simulator/background-source-changed", notes: [
            "the original on the Mac was modified (4 KiB at 22 MiB) after the first part verified",
            "result: version \(firstVersion) -> \(view.job.itemVersionID); kept \(change.fields["kept_parts"] ?? "?") verified parts; imported SHA-256 \(after) is the new file, never a mix",
        ])
    }

    @Test func revokedCredentialBlocksAndKeepsVerifiedBytesAcrossARelaunch() async throws {
        let client = try TestClient.make("revoke")
        await client.coordinator.start()
        let (paired, token) = try await client.pair("SLOW", deviceName: "Simulator background revoke")
        let itemID = try await client.itemID(paired.sourceID, titled: "revocable")
        let jobID = try await client.coordinator.startJob(sourceID: paired.sourceID, itemID: itemID, title: "revocable")
        _ = try await client.wait(jobID, seconds: 60) { $0.verifiedParts >= 2 }
        // Revoked (here by the phone itself; the Mac owner's revocation gives the same 401).
        let endpoint = try #require(paired.endpoints.first?.baseURL())
        try await SourceClient(baseURL: endpoint, pin: try SPKIPin(hex: paired.spkiSHA256), sourceID: paired.sourceID, token: token)
            .revoke(deviceID: paired.deviceID)
        let paused = try await client.wait(jobID, seconds: 60) { $0.job.state == .paused }
        #expect(paused.job.pauseReason == .reauthenticationRequired)
        let verified = paused.verifiedParts
        #expect(verified >= 2)
        client.coordinator.invalidate()

        // "Relaunch": a new coordinator over the same store. Blocked, nothing requested, verified parts kept.
        let relaunched = try TestClient.make("revoke", root: client.root)
        defer { relaunched.cleanUp(); client.cleanUp() }
        let summary = await relaunched.coordinator.start()
        #expect(summary.keptVerifiedParts == verified)
        #expect(summary.enqueued == 0)
        try await Task.sleep(for: .seconds(1))
        let after = try #require(relaunched.coordinator.job(jobID))
        #expect(after.job.state == .paused && after.job.pauseReason == .reauthenticationRequired)
        #expect(after.verifiedParts == verified)
        #expect(after.progress.verifiedBytes > 0)
        relaunched.writeEvidence("simulator/background-revoked", notes: [
            "revoked after \(verified) verified parts; job paused with reauthentication_required (next step: \(PauseReason.reauthenticationRequired.nextStep))",
            "relaunch over the same store: kept \(summary.keptVerifiedParts) verified parts, enqueued \(summary.enqueued); verified bytes \(after.progress.verifiedBytes)",
        ])
    }

    /// Manual address entry and the intended address forms (plan 15.1, 15.2 gate, T43). Each form is
    /// pinned again before use, then a 20 MiB item is downloaded through the background session.
    @Test func manualAddressFormsWorkThroughTheBackgroundSession() async throws {
        let client = try TestClient.make("addresses")
        defer { client.cleanUp() }
        await client.coordinator.start()
        let (paired, _) = try await client.pair("MAIN", deviceName: "Simulator background addresses")
        let port = try SimEnvironment.source("MAIN").port
        var forms: [(String, String, Bool)] = [("IPv4 loopback", "127.0.0.1", false), ("IPv6 loopback", "::1", false)]
        let env = SimEnvironment.values
        if let lan = env["G02_LAN_IP"], !lan.isEmpty { forms.append(("LAN IPv4", lan, false)) }
        if let local = env["G02_LOCAL_HOSTNAME"], !local.isEmpty { forms.append(("Bonjour .local host name", local, false)) }
        if let tailscale = env["G02_TAILSCALE_IP"], !tailscale.isEmpty { forms.append(("Tailscale IPv4", tailscale, true)) }
        if let magic = env["G02_MAGICDNS"], !magic.isEmpty { forms.append(("Tailscale MagicDNS name", magic, true)) }
        var notes: [String] = []
        for (label, host, tailnet) in forms {
            let endpoint = PairingPayload.Endpoint(host: host, port: port)
            do {
                _ = try await client.coordinator.verifyAndPreferEndpoint(sourceID: paired.sourceID, endpoint: endpoint)
                // The harness has no ATS key: ATS refuses these hosts after the pin matched (ats/ats-probe-none.log).
                #expect(!tailnet, "\(label) worked without an ATS exception; re-check the ATS finding")
            } catch {
                if tailnet {
                    #expect(error == .tlsFailure, "\(label): \(error)")
                    notes.append("REFUSED (expected) \(label) (\(host)): pinned capabilities ended in \(error): ATS requires default trust for this host; see ats/ats-probe-*.log")
                } else {
                    Issue.record("\(label) \(host): pinned capabilities failed: \(error)")
                    notes.append("FAIL \(label) (\(host)): pinned capabilities: \(error)")
                }
                continue
            }
            let itemID = try await client.itemID(paired.sourceID, titled: "sim-small")
            let jobID = try await client.coordinator.startJob(sourceID: paired.sourceID, itemID: itemID, title: "sim-small")
            let view = try await client.wait(jobID, seconds: 120) { $0.job.state == .imported || $0.job.state == .paused }
            let events = client.coordinator.log.allEntries()
            let hosts = Set(events.filter { $0.event == "part_requested" && $0.fields["job"] == jobID }.compactMap { $0.fields["host"] })
            let assembled = events.contains { $0.event == "assembly_verified" && $0.fields["job"] == jobID }
            #expect(view.job.state == .imported && assembled, "\(label)")
            #expect(hosts == [host], "\(label): parts went to \(hosts)")
            notes.append("\(view.job.state == .imported && assembled ? "PASS" : "FAIL") \(label) (\(host)): pinned capabilities ok; background download \(view.job.state.rawValue), full SHA-256 \(assembled ? "matched" : "not reached"), parts requested from \(hosts.sorted())")
        }
        let missing = ["G02_LAN_IP", "G02_LOCAL_HOSTNAME", "G02_TAILSCALE_IP", "G02_MAGICDNS"].filter { (env[$0] ?? "").isEmpty }
        if !missing.isEmpty { notes.append("not available on this Mac (not run): \(missing.joined(separator: ", "))") }
        client.writeEvidence("simulator/background-address-forms", notes: notes)
    }

    /// Bonjour (NSBonjourServices `_sylvia-src._tcp`): the simulator finds the source, resolves it, and the
    /// resolved address is used only after the pinned key matches.
    @Test func bonjourBrowseFindsResolvesAndPinsTheSource() async throws {
        let info = try SimEnvironment.source("MAIN")
        let client = try TestClient.make("bonjour")
        defer { client.cleanUp() }
        await client.coordinator.start()
        let (paired, _) = try await client.pair("MAIN", deviceName: "Simulator Bonjour")
        let found = await Self.browse(sourceID: info.source_id, timeout: .seconds(20))
        let result = try #require(found, "no _sylvia-src._tcp result with this source ID")
        let resolved = try #require(await BonjourBrowser.resolveIPv4(result.endpoint), "could not resolve \(result.name)")
        let capabilities = try await client.coordinator.verifyAndPreferEndpoint(sourceID: paired.sourceID, endpoint: resolved)
        #expect(capabilities.sourceID == info.source_id)
        client.writeEvidence("simulator/bonjour-browse", notes: [
            "NWBrowser bonjourWithTXTRecord(_sylvia-src._tcp) found \"\(result.name)\" with TXT sid = the paired source ID",
            "resolved over TCP to \(resolved.urlHost):\(resolved.port); pinned GET /v1/capabilities through that address returned the paired source",
            "the simulator shows no local-network permission prompt; prompt and denial are device checklist steps",
        ])
    }

    /// Pull-first device inbox (plan 15.1, round 2 gate gap): the MAIN source queues `sim-small` for every device
    /// that pairs (`--test-send-on-pair`, as the `send` command does). The phone lists its inbox (the Mac's entry
    /// becomes observed by phone), downloads the entry through the background session, imports it once, and its
    /// receipts move the Mac's entry to downloaded to phone and imported into Sylvia.
    @Test func deviceInboxEntryIsObservedDownloadedAndImported() async throws {
        let client = try TestClient.make("inbox")
        defer { client.cleanUp() }
        await client.coordinator.start()
        let (paired, _) = try await client.pair("MAIN", deviceName: "Simulator inbox")
        var entries: [InboxEntry] = []
        let deadline = ContinuousClock.now + .seconds(20)
        while entries.isEmpty, ContinuousClock.now < deadline {
            entries = try await client.coordinator.inbox(sourceID: paired.sourceID)
            if entries.isEmpty { try await Task.sleep(for: .milliseconds(250)) }
        }
        let entry = try #require(entries.first, "nothing was queued for this device")
        #expect(entries.count == 1 && entry.title == "sim-small")
        #expect(entry.state == .observedByPhone)
        let jobID = try await client.coordinator.startJob(
            sourceID: paired.sourceID, itemID: entry.itemID, title: entry.title, queueEntryID: entry.queueEntryID)
        let view = try await client.wait(jobID, seconds: 120) { $0.job.state == .imported && $0.job.receiptsAcknowledged }
        #expect(view.job.state == .imported && view.job.queueEntryID == entry.queueEntryID)
        let after = try await client.coordinator.inbox(sourceID: paired.sourceID)
        let onMac = after.first { $0.queueEntryID == entry.queueEntryID }?.state
        #expect(onMac == .importedIntoSylvia)
        let acknowledgements = client.coordinator.log.allEntries().filter { $0.event == "receipt_acknowledged" && $0.fields["job"] == jobID }
        #expect(acknowledgements.map { $0.fields["entry_state"] } == ["downloaded_to_phone", "imported_into_sylvia"])
        client.writeEvidence("simulator/background-device-inbox", notes: [
            "MAIN queued sim-small for this device after pairing (--test-send-on-pair); first inbox listing: \(entries.count) entry, state \(entry.state.rawValue)",
            "background download with the entry's ID: \(view.job.state.rawValue), \(view.progress.totalBytes) bytes; receipts acknowledged with entry states \(acknowledgements.compactMap { $0.fields["entry_state"] })",
            "inbox listed again after the import: entry state \(onMac?.rawValue ?? "missing") (the Mac's own record)",
        ])
    }

    struct BrowseResult: Sendable {
        var name: String
        var endpoint: NWEndpoint
    }

    static func browse(sourceID: String, timeout: Duration) async -> BrowseResult? {
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_sylvia-src._tcp", domain: nil), using: .tcp)
        let result: BrowseResult? = await withCheckedContinuation { continuation in
            let once = OnceFlag()
            browser.browseResultsChangedHandler = { results, _ in
                for result in results {
                    guard case .service(let name, _, _, _) = result.endpoint, case .bonjour(let txt) = result.metadata,
                        txt["sid"] == sourceID
                    else { continue }
                    if once.claim() { continuation.resume(returning: BrowseResult(name: name, endpoint: result.endpoint)) }
                }
            }
            browser.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(Int(timeout.components.seconds))) {
                if once.claim() { continuation.resume(returning: nil) }
            }
        }
        browser.cancel()
        return result
    }
}
