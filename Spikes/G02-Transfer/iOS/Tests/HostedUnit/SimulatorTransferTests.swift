import Foundation
import Security
import Synchronization
import Testing
import SylviaTransferClient
import SylviaTransferCore

/// Foreground pairing and verified download from the iOS simulator to the command-line Mac source
/// (`sylvia-source`) running on the host, through the shared TransferKit code. Driven by
/// Spikes/G02-Transfer/Scripts/simulator-pairing-run.sh, which starts the source, writes the pairing code
/// to a file only this run can read, answers the Mac's approval prompt and passes these variables through
/// xcodebuild (TEST_RUNNER_ prefix):
///
///   G02_PAIRING_CODE_FILE   file holding one pairing code (the secret never appears in arguments or logs)
///   G02_TITLE               catalog title to download
///   G02_EXPECTED_SHA256     SHA-256 of the original file on the Mac
///
/// This proves the protocol core, pinning, Keychain storage and part validation work on iOS with
/// foreground URLSession tasks. Background URLSession download tasks are G0.2 part 2; a physical device
/// is a checklist item. Without the variables the suite is disabled with that reason (the script checks
/// that it ran).
@Suite("Simulator to Mac source: pinned pairing and verified download")
struct SimulatorTransferTests {
    static let environment = ProcessInfo.processInfo.environment
    static let codeFile = environment["G02_PAIRING_CODE_FILE"]

    @Test(.enabled(if: codeFile != nil, "run by Spikes/G02-Transfer/Scripts/simulator-pairing-run.sh"))
    func pairsPinsStoresTheTokenAndDownloadsVerifiedBytes() async throws {
        let code = try String(contentsOfFile: try #require(Self.codeFile), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = try #require(Self.environment["G02_TITLE"])
        let expected = try #require(Self.environment["G02_EXPECTED_SHA256"])
        let payload = try PairingPayload.decode(code, now: Date())
        let pin = try payload.pin
        var lines = ["simulator: iOS \(ProcessInfo.processInfo.operatingSystemVersionString), hosted test in G02TransferHarness"]
        lines.append("endpoints: \(payload.endpoints.map { "\($0.urlHost):\($0.port)" }.joined(separator: " "))")
        lines.append("pinned fingerprint: \(pin.displayFingerprint)")

        // 1. A wrong pin aborts in the TLS handshake: nothing is sent, the invitation stays usable.
        var forged = payload
        forged.spkiSHA256 = SHA256Hex.digest(Data("not the source".utf8))
        await #expect(throws: ClientError.pinMismatch) {
            _ = try await SourceClient.pair(payload: forged, deviceID: CanonicalID.make(), deviceName: "Forged pin")
        }
        lines.append("wrong pin: pairing refused with pinMismatch before any request")

        // 2. Genuine pairing (the script approves on the Mac), token into the Keychain.
        let deviceID = CanonicalID.make()
        let (paired, token) = try await SourceClient.pair(payload: payload, deviceID: deviceID, deviceName: "iOS Simulator")
        #expect(paired.spkiSHA256 == pin.hex && paired.sourceID == payload.sourceID)
        let store = KeychainCredentialStore(service: "com.jevidon.sylvia.spike.transfer-sim.\(UUID().uuidString)")
        defer { try? store.deleteToken(sourceID: paired.sourceID) }
        try store.saveToken(token, sourceID: paired.sourceID)
        #expect(try store.storedAccessibility(sourceID: paired.sourceID) == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String))
        let stored = try #require(try store.token(sourceID: paired.sourceID))
        lines.append("paired as \(deviceID); token stored in the Keychain (after first unlock, this device only) and read back")

        // 3. Authenticated, pinned requests with the stored token; verified part-by-part download.
        let endpoint = try #require(paired.endpoints.first?.baseURL())
        let client = SourceClient(baseURL: endpoint, pin: pin, sourceID: paired.sourceID, token: stored)
        let tls = Mutex<[String]>([])
        client.observeConnectionMetrics { version, alpn in
            tls.withLock { $0.append("\(version.map { String(describing: $0) } ?? "nil") \(alpn ?? "nil")") }
        }
        let capabilities = try await client.capabilities()
        let item = try #require(try await client.catalog().items.first { $0.title == title })
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("g02-sim-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        let parts = Mutex(0)
        let engine = TransferEngine(client: client, itemID: item.itemID, stagingRoot: staging) { event in
            if case .partVerified = event { parts.withLock { $0 += 1 } }
        }
        guard case .ready(let manifest, let assets) = await engine.run() else {
            Issue.record("transfer did not finish")
            return
        }
        let asset = try #require(assets.first)
        #expect(asset.sha256 == expected)
        let handedOff = try Data(contentsOf: asset.url)
        #expect(SHA256Hex.digest(handedOff) == expected)
        lines.append("capabilities: protocol \(capabilities.protocolVersion), default part size \(capabilities.partSize.defaultBytes) bytes")
        lines.append("downloaded \"\(title)\": \(manifest.totalBytes) bytes in \(parts.withLock { $0 }) verified parts; full SHA-256 \(asset.sha256) matches the original")

        // 4. Receipt, then self-revocation: the token stops working.
        let ack = try await client.postReceipt(Receipt(
            receiptID: CanonicalID.make(), queueEntryID: nil, itemID: item.itemID, itemVersionID: manifest.itemVersionID,
            state: .downloadedToPhone, occurredAt: Date()))
        #expect(!ack.duplicate)
        try await client.revoke(deviceID: deviceID)
        await #expect(throws: ClientError.http(status: 401, code: "unauthenticated")) { _ = try await client.catalog() }
        lines.append("receipt downloaded_to_phone acknowledged; self-revocation made the token fail with 401")
        try await Task.sleep(for: .milliseconds(200))
        lines.append("negotiated TLS and ALPN per request: \(Set(tls.withLock { $0 }).sorted().joined(separator: ", "))")
        #expect(tls.withLock { $0 }.allSatisfy { $0.contains("772") || $0.contains("TLSv13") })
        for line in lines { print("G02-SIM: \(line)") }
    }
}
