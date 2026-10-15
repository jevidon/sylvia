import Foundation
import Synchronization
import Testing
@_spi(Testing) import SylviaSourceService
@_spi(Testing) import SylviaTransferClient
import SylviaTransferCore

/// The Mac side beyond the HTTP contract: the durable outbound queue and idempotent receipts (plan 16.2),
/// Bonjour advertisement (15.1), source-root containment (16.3), idle-connection limits, and the
/// Keychain-backed identity store (ADR-0008). Environment: host (macOS), in-process source, real TLS.
@Suite("Mac source: queue, receipts, discovery, containment (16.2, 16.3)", .serialized)
struct SourceSideTests {
    // MARK: Queue and receipts

    @Test func queueAndReceiptsKeepTheThreeAcknowledgementsApartAndAreIdempotent() async throws {
        let harness = try await Harness.make(files: ["walden.epub": Harness.bytes(seed: 40, count: 5000)])
        let (client, paired, token) = try await harness.pairDevice()
        let (otherClient, _, _) = try await harness.pairDevice(name: "Other phone")
        let itemID = try await harness.itemID(titled: "walden")

        // "Send to device" prepares an immutable version and queues it durably: Queued on Mac.
        let entry = try await harness.service.send(itemID: itemID, toDevice: paired.deviceID)
        #expect(entry.state == .queuedOnMac)
        #expect(entry.itemVersionID != nil)

        // Listing the inbox marks the entry observed; it never implies download or import.
        let inbox = try await client.deviceInbox()
        #expect(inbox.entries.map(\.queueEntryID) == [entry.queueEntryID])
        #expect(inbox.entries.first?.state == .observedByPhone)
        #expect(inbox.entries.first?.itemVersionID == entry.itemVersionID)
        Evidence.write("captured/device-inbox-page.json", String(decoding: try TransferJSON.encode(inbox), as: UTF8.self))
        // Another device sees nothing of this device's queue.
        #expect(try await otherClient.deviceInbox().entries.isEmpty)

        let versionID = try #require(entry.itemVersionID)
        let downloaded = Receipt(
            receiptID: CanonicalID.make(), queueEntryID: entry.queueEntryID, itemID: itemID, itemVersionID: versionID,
            state: .downloadedToPhone, occurredAt: harness.clock.now())
        Evidence.write("captured/receipt-downloaded.json", String(decoding: try TransferJSON.encode(downloaded), as: UTF8.self))
        let firstAck = try await client.postReceipt(downloaded)
        #expect(firstAck.entryState == .downloadedToPhone && !firstAck.duplicate)

        // A lost acknowledgement is retried with the same receipt ID: acknowledged again, no change.
        let retried = try await client.postReceipt(downloaded)
        #expect(retried.duplicate && retried.entryState == .downloadedToPhone)

        // The same receipt ID with different content is a conflict, not a silent overwrite.
        var altered = downloaded
        altered.state = .importedIntoSylvia
        await #expect(throws: ClientError.http(status: 409, code: "receipt_conflict")) { _ = try await client.postReceipt(altered) }

        // Another device cannot acknowledge this device's entry.
        let foreign = Receipt(
            receiptID: CanonicalID.make(), queueEntryID: entry.queueEntryID, itemID: itemID, itemVersionID: versionID,
            state: .importedIntoSylvia, occurredAt: harness.clock.now())
        await #expect(throws: ClientError.http(status: 404, code: "not_found")) { _ = try await otherClient.postReceipt(foreign) }

        // An import failure is shown and the entry is kept for retry.
        let failed = Receipt(
            receiptID: CanonicalID.make(), queueEntryID: entry.queueEntryID, itemID: itemID, itemVersionID: versionID,
            state: .importFailed, occurredAt: harness.clock.now(), failure: .init(code: "unsupported_format", message: "Not a valid EPUB."))
        #expect(try await client.postReceipt(failed).entryState == .importFailed)
        let afterFailure = await harness.service.queue.entries()
        #expect(afterFailure.count == 1 && afterFailure[0].lastFailure?.code == "unsupported_format")

        // A failure that breaks receipt.v1 (code pattern, message length) is refused, not stored for display.
        for bad in [Receipt.Failure(code: "Not A Code", message: "x"), .init(code: "too_long", message: String(repeating: "m", count: 513)),
                    .init(code: "control", message: "line\u{0007}bell")] {
            let rejected = Receipt(
                receiptID: CanonicalID.make(), queueEntryID: entry.queueEntryID, itemID: itemID, itemVersionID: versionID,
                state: .importFailed, occurredAt: harness.clock.now(), failure: bad)
            await #expect(throws: ClientError.http(status: 400, code: "invalid_request")) { _ = try await client.postReceipt(rejected) }
        }
        #expect(await harness.service.queue.entries()[0].lastFailure?.code == "unsupported_format")

        // Imported into Sylvia is a separate, final acknowledgement; a late "downloaded" never moves it back.
        let imported = Receipt(
            receiptID: CanonicalID.make(), queueEntryID: entry.queueEntryID, itemID: itemID, itemVersionID: versionID,
            state: .importedIntoSylvia, occurredAt: harness.clock.now())
        Evidence.write("captured/receipt-imported.json", String(decoding: try TransferJSON.encode(imported), as: UTF8.self))
        #expect(try await client.postReceipt(imported).entryState == .importedIntoSylvia)
        let late = Receipt(
            receiptID: CanonicalID.make(), queueEntryID: entry.queueEntryID, itemID: itemID, itemVersionID: versionID,
            state: .downloadedToPhone, occurredAt: harness.clock.now())
        #expect(try await client.postReceipt(late).entryState == .importedIntoSylvia)

        // A receipt that names a different item than the entry is refused.
        let mismatched = Receipt(
            receiptID: CanonicalID.make(), queueEntryID: entry.queueEntryID, itemID: CanonicalID.make(), itemVersionID: versionID,
            state: .downloadedToPhone, occurredAt: harness.clock.now())
        await #expect(throws: ClientError.http(status: 400, code: "invalid_request")) { _ = try await client.postReceipt(mismatched) }

        // The source file is untouched by any of this.
        #expect(try Data(contentsOf: harness.root.appendingPathComponent("walden.epub")) == Data(Harness.bytes(seed: 40, count: 5000)))

        // Queue and receipt ledger survive a relaunch: the retried receipt is still a duplicate.
        let relaunched = try await harness.restarted()
        let entries = await relaunched.service.queue.entries()
        #expect(entries.map(\.queueEntryID) == [entry.queueEntryID] && entries[0].state == .importedIntoSylvia)
        #expect(try await relaunched.client(token: token).postReceipt(downloaded).duplicate)
        await relaunched.cleanUp()
    }

    @Test func queuedItemFollowsANewVersionWhenTheOriginalChanges() async throws {
        let harness = try await Harness.make(files: ["a.pdf": Harness.bytes(seed: 41, count: 3000)])
        let (client, paired, _) = try await harness.pairDevice()
        let itemID = try await harness.itemID(titled: "a")
        let entry = try await harness.service.send(itemID: itemID, toDevice: paired.deviceID)
        try Data(Harness.bytes(seed: 42, count: 3001)).write(to: harness.root.appendingPathComponent("a.pdf"))
        // The old version is gone; the inbox shows no stale version as current.
        let listed = try await client.deviceInbox().entries.first
        #expect(listed?.queueEntryID == entry.queueEntryID)
        #expect(listed?.itemVersionID != entry.itemVersionID)
        // Fetching the manifest prepares the new version, which the inbox then reports.
        let manifest = try await client.manifest(itemID: itemID)
        #expect(manifest.itemVersionID != entry.itemVersionID)
        #expect(try await client.deviceInbox().entries.first?.itemVersionID == manifest.itemVersionID)
        await harness.cleanUp()
    }

    // MARK: Containment and connection limits

    @Test func aFolderSwappedForASymbolicLinkIsNotFollowed() async throws {
        let harness = try await Harness.make(files: ["Book/01.mp3": Harness.bytes(seed: 43, count: 2000)])
        let (client, _, _) = try await harness.pairDevice()
        let itemID = try await harness.itemID(titled: "Book")
        // Outside the source root, a file with the same relative name.
        let outside = harness.root.deletingLastPathComponent().appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("private file outside the shared folder".utf8).write(to: outside.appendingPathComponent("01.mp3"))
        // After the scan, the shared folder is replaced by a link to the outside folder.
        let folder = harness.root.appendingPathComponent("Book")
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: outside)
        await #expect(throws: ClientError.http(status: 404, code: "source_unavailable")) { _ = try await client.manifest(itemID: itemID) }
        // Nothing was snapshotted (the item had never been prepared, and preparing it was refused).
        let snapshots = harness.state.appendingPathComponent("snapshots")
        let files = (FileManager.default.subpaths(atPath: snapshots.path) ?? []).filter {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: snapshots.appendingPathComponent($0).path, isDirectory: &isDirectory)
            return !isDirectory.boolValue
        }
        #expect(files.isEmpty, "nothing from outside the root was snapshotted")
        await harness.cleanUp()
    }

    @Test func anOpenSnapshotKeepsServingItsVersionAfterInvalidation() async throws {
        let original = Harness.bytes(seed: 44, count: 4000)
        let harness = try await Harness.make(files: ["b.pdf": original])
        let itemID = try await harness.itemID(titled: "b")
        _ = try await harness.service.library.prepare(itemID: itemID)
        let manifest = try await harness.service.library.manifest(itemID: itemID, sourceID: harness.service.sourceID, partSize: nil)
        let assetID = manifest.assets[0].assetID
        guard case .current(let first) = await harness.service.library.serveInfo(assetID: assetID) else {
            Issue.record("expected a current version")
            return
        }
        // The original changes; the next lookup invalidates the version and deletes its snapshot.
        try Data(Harness.bytes(seed: 45, count: 4000)).write(to: harness.root.appendingPathComponent("b.pdf"))
        guard case .noCurrentVersion = await harness.service.library.serveInfo(assetID: assetID) else {
            Issue.record("expected the changed original to invalidate the version")
            return
        }
        let snapshots = harness.state.appendingPathComponent("snapshots/\(manifest.itemVersionID)")
        #expect(!FileManager.default.fileExists(atPath: snapshots.path))
        // A response already holding the descriptor still reads exactly the old version's bytes.
        #expect(first.read(offset: 0, count: 4000) == original)
        #expect(first.etag == manifest.assets[0].etag)
        await harness.cleanUp()
    }

    @Test func idleConnectionsAreClosed() async throws {
        let harness = try await Harness.make(idleTimeout: .seconds(1))
        let socket = try Self.connect(port: harness.service.port)
        defer { close(socket) }
        // Send nothing (not even a TLS ClientHello). The source closes the connection.
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let start = ContinuousClock.now
        var byte: UInt8 = 0
        let read = recv(socket, &byte, 1, 0)
        let elapsed = ContinuousClock.now - start
        #expect(read == 0, "the source closed the idle connection (recv returned \(read), errno \(errno))")
        #expect(elapsed < .seconds(4))
        await harness.cleanUp()
    }

    static func connect(port: Int) throws -> Int32 {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard result == 0 else {
            close(descriptor)
            throw POSIXError(.ECONNREFUSED)
        }
        return descriptor
    }

    // MARK: Discovery

    @Test func advertisesTheProductSpecificBonjourServiceType() async throws {
        let name = "Sylvia test \(UUID().uuidString.prefix(8))"
        let harness = try await Harness.make(sourceName: name, advertiseBonjour: true)
        #expect(harness.service.bonjourStatus == 0)
        #expect(BonjourAdvertiser.serviceType == "_sylvia-src._tcp")
        // Browse with the system's dns-sd tool, independently of the advertiser's code.
        let output = try await Self.browse(BonjourAdvertiser.serviceType, seconds: 3)
        let found = output.split(separator: "\n").contains { $0.contains(BonjourAdvertiser.serviceType) && $0.contains(name) }
        Evidence.write("bonjour-browse.txt", "host (macOS): dns-sd -B \(BonjourAdvertiser.serviceType) while the in-process source "
            + "(bound to 127.0.0.1, registered local-only) was advertising as \"\(name)\"\n" + output)
        #expect(found, "dns-sd saw the advertisement")
        await harness.service.stop()
        await harness.cleanUp()
    }

    static func browse(_ type: String, seconds: Int) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dns-sd")
        process.arguments = ["-B", type, "local."]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        try await Task.sleep(for: .seconds(seconds))
        process.terminate()
        process.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    // MARK: Identity in the Keychain

    /// Review finding R1-11: by default the store uses only the data protection keychain. In this unsigned test
    /// binary (no keychain access group) that is errSecMissingEntitlement, thrown, with nothing written anywhere;
    /// the login keychain is used only when the caller opts in, as the command-line tools do.
    @Test func keychainIdentityStoreNeverFallsBackToTheLoginKeychainUnlessAskedTo() throws {
        let state = FileManager.default.temporaryDirectory.appendingPathComponent("g02-identity-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: state) }
        let service = "com.jevidon.sylvia.spike.source-identity-test.\(UUID().uuidString)"
        let strict = KeychainIdentityStore(service: service, stateDirectory: state)
        #expect(throws: KeychainStatusError(status: errSecMissingEntitlement)) { _ = try strict.loadOrCreate(now: Date()) }
        #expect(strict.lastBackend == nil)
        #expect(!FileManager.default.fileExists(atPath: state.appendingPathComponent("identity.json").path))
        let fallback = KeychainIdentityStore(service: service, stateDirectory: state, policy: .allowLoginKeychainFallback)
        defer { try? fallback.reset() }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        query[kSecReturnAttributes as String] = true
        var found: CFTypeRef?
        #expect(SecItemCopyMatching(query as CFDictionary, &found) == errSecItemNotFound, "the strict store wrote a key to the login keychain")
        Evidence.write("keychain-identity-policy.txt", """
            host (macOS): KeychainIdentityStore with its default policy (dataProtectionOnly) in the unsigned swift test binary
            loadOrCreate threw errSecMissingEntitlement (\(errSecMissingEntitlement)); no identity.json was written and the login
            keychain holds no item for the service: no silent fallback to the weaker store (review finding R1-11)

            """)
    }

    @Test func keychainIdentityStoreKeepsTheKeyAndReloadsTheSameIdentity() throws {
        let state = FileManager.default.temporaryDirectory.appendingPathComponent("g02-identity-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: state) }
        let store = KeychainIdentityStore(
            service: "com.jevidon.sylvia.spike.source-identity-test.\(UUID().uuidString)", stateDirectory: state,
            policy: .allowLoginKeychainFallback)
        defer { try? store.reset() }
        let (created, isNew) = try store.loadOrCreate(now: Date())
        #expect(isNew)
        let backend = try #require(store.lastBackend)
        let (reloaded, isNewAgain) = try store.loadOrCreate(now: Date())
        #expect(!isNewAgain)
        #expect(reloaded.pin == created.pin && reloaded.sourceID == created.sourceID)
        #expect(reloaded.privateKey.rawRepresentation == created.privateKey.rawRepresentation)
        // The private key is not in the state directory; only the public certificate is.
        let files = try FileManager.default.contentsOfDirectory(atPath: state.path)
        #expect(files == ["identity.json"])
        let publicPart = try String(contentsOf: state.appendingPathComponent("identity.json"), encoding: .utf8)
        #expect(!publicPart.contains(created.privateKey.rawRepresentation.base64EncodedString()))
        #expect(!publicPart.contains(created.privateKey.pemRepresentation))
        // A reset makes a new key: every phone must pair again.
        try store.reset()
        let (fresh, freshIsNew) = try store.loadOrCreate(now: Date())
        #expect(freshIsNew && fresh.pin != created.pin)
        Evidence.write("keychain-identity.txt", """
            host (macOS): KeychainIdentityStore round trip from the unsigned swift test binary, policy allowLoginKeychainFallback
            (what the command-line tools use; the companion uses dataProtectionOnly)
            backend used: \(backend.rawValue)
            created, reloaded with the same SPKI pin and source ID; state directory holds only identity.json (public certificate)
            reset produced a new key (new pin), so paired phones must pair again

            """)
    }

    // MARK: Pairing payloads for schema validation (secrets replaced)

    @Test func capturesPairingPayloadsWithSecretsReplaced() async throws {
        let harness = try await Harness.make()
        let payload = await harness.service.issueInvitation()
        var redacted = payload
        // Placeholders with the same shape as the real values; the real secret and token never reach a file.
        redacted.invitationSecret = Base64URL.encode([UInt8](repeating: 0xA5, count: 32))
        Evidence.write("captured/pairing-payload.json", String(decoding: try TransferJSON.encode(redacted), as: UTF8.self))
        let deviceID = CanonicalID.make()
        let request = PairRequest(
            invitationID: payload.invitationID, invitationSecret: redacted.invitationSecret, sourceID: payload.sourceID,
            deviceID: deviceID, deviceName: "Test iPhone")
        Evidence.write("captured/pair-request.json", String(decoding: try TransferJSON.encode(request), as: UTF8.self))
        let real = PairRequest(
            invitationID: payload.invitationID, invitationSecret: payload.invitationSecret, sourceID: payload.sourceID,
            deviceID: deviceID, deviceName: "Test iPhone")
        let raw = try await harness.unauthenticatedClient().raw(
            method: "POST", pathAndQuery: "/v1/pair", headers: ["Content-Type": "application/json"], body: try TransferJSON.encode(real))
        #expect(raw.status == 200)
        var response = try TransferJSON.decode(PairResponse.self, from: raw.body)
        response.token = Base64URL.encode([UInt8](repeating: 0x5A, count: 32))
        Evidence.write("captured/pair-response.json", String(decoding: try TransferJSON.encode(response), as: UTF8.self))
        await harness.cleanUp()
    }
}
