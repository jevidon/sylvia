import Foundation
import SylviaTransferClient
import SylviaTransferCore

/// `sylvia-fetch`: a command-line stand-in for the phone, for scripted runs against `sylvia-source`.
///
/// Reads one pairing code from stdin (never from arguments, which other processes can see), pins the
/// source key from it, pairs, then downloads either the first item queued for this device or a catalog
/// item by title, verifying every part and the whole file. It posts the "downloaded to phone" receipt
/// and, after copying the verified file to --out, an "imported into Sylvia" receipt. That copy stands in
/// for the importer, which is not part of this spike; the log says so. The token stays in memory.
@main
struct SylviaFetchCommand {
    static let usage = """
        usage: sylvia-fetch --out DIR [--device-name NAME] (--inbox SECONDS | --title TITLE)
          reads the pairing code (SYLVIA1-... or sylvia://pair/v1#...) from stdin
          --inbox SECONDS   wait up to SECONDS for an entry queued for this device, then download it
          --title TITLE     download the catalog item with this title
          --part-size-mib N request this part size (default: the source's default)
          --only-host HOST  use only the payload endpoints with this host (to exercise one address form)
        """

    static func main() async {
        var out: URL?
        var deviceName = "sylvia-fetch"
        var inboxWait: Double?
        var title: String?
        var partSize: Int64?
        var onlyHost: String?
        var arguments = Array(CommandLine.arguments.dropFirst())
        while !arguments.isEmpty {
            let name = arguments.removeFirst()
            guard !arguments.isEmpty else { fail("\(name) needs a value") }
            let value = arguments.removeFirst()
            switch name {
            case "--out": out = URL(fileURLWithPath: value, isDirectory: true)
            case "--device-name": deviceName = value
            case "--inbox": inboxWait = Double(value)
            case "--title": title = value
            case "--part-size-mib": partSize = Int64(value).map { $0 * TransferProtocol.mebibyte }
            case "--only-host": onlyHost = value
            default: fail("unknown option \(name)")
            }
        }
        guard let out, (inboxWait == nil) != (title == nil) else { fail("give --out and exactly one of --inbox or --title") }
        guard let code = readLine(strippingNewline: true) else { fail("no pairing code on stdin") }
        do {
            try await run(code: code, deviceName: deviceName, out: out, inboxWait: inboxWait, title: title, partSize: partSize, onlyHost: onlyHost)
        } catch {
            say("error: \(error)")
            exit(1)
        }
    }

    static func run(code: String, deviceName: String, out: URL, inboxWait: Double?, title: String?, partSize: Int64?, onlyHost: String?) async throws {
        var payload = try PairingPayload.decode(code, now: Date())
        if let onlyHost {
            payload.endpoints = payload.endpoints.filter { $0.host == onlyHost }
            guard !payload.endpoints.isEmpty else { throw FetchError.noSuchEndpoint }
        }
        let pin = try payload.pin
        say("source \(payload.sourceName) (\(payload.sourceID))")
        say("pinned fingerprint: \(pin.displayFingerprint)")
        say("endpoints: \(payload.endpoints.map { "\($0.urlHost):\($0.port)" }.joined(separator: " "))")
        let deviceID = CanonicalID.make()
        say("device id: \(deviceID)")
        say("pairing; approve on the Mac")
        let (paired, token) = try await SourceClient.pair(payload: payload, deviceID: deviceID, deviceName: deviceName)
        say("paired; scopes \(paired.scopes.map(\.rawValue).joined(separator: ","))")

        // Use the first endpoint that answers, with the stored pin and the new token.
        var client: SourceClient?
        for endpoint in paired.endpoints {
            guard let base = endpoint.baseURL() else { continue }
            let candidate = SourceClient(baseURL: base, pin: pin, sourceID: paired.sourceID, token: token)
            if (try? await candidate.capabilities()) != nil {
                client = candidate
                say("connected via \(endpoint.urlHost):\(endpoint.port)")
                break
            }
        }
        guard let client else { throw FetchError.unreachable }

        var itemID: String
        var queueEntryID: String?
        if let inboxWait {
            let deadline = Date().addingTimeInterval(inboxWait)
            var found: InboxEntry?
            while found == nil, Date() < deadline {
                found = try await client.deviceInbox().entries.first { $0.state == .queuedOnMac || $0.state == .observedByPhone }
                if found == nil { try await Task.sleep(for: .milliseconds(250)) }
            }
            guard let found else { throw FetchError.nothingQueued }
            itemID = found.itemID
            queueEntryID = found.queueEntryID
            say("inbox entry \(found.queueEntryID) item \(found.itemID) state \(found.state.rawValue)")
        } else {
            let page = try await client.catalog()
            guard let item = page.items.first(where: { $0.title == title }) else { throw FetchError.noSuchTitle }
            itemID = item.itemID
            say("catalog item \(item.itemID) (\(item.assetCount) file(s), \(item.totalBytes) bytes)")
        }

        let staging = out.appendingPathComponent(".staging", isDirectory: true)
        var options = TransferEngine.Options()
        options.preferredPartSize = partSize
        let engine = TransferEngine(client: client, itemID: itemID, stagingRoot: staging, options: options) { event in
            switch event {
            case .sourcePreparing: say("the Mac is preparing the item; asking again shortly")
            case .partFailed(_, let index, let failure): say("part \(index) failed: \(failure); recovery \(failure.recovery)")
            case .versionChanged(let from, let to, let kept, let discarded):
                say("version changed \(from) -> \(to); kept \(kept) parts, discarded \(discarded)")
            case .paused(let reason): say("paused: \(reason.rawValue): \(reason.nextStep)")
            default: break
            }
        }
        let outcome = await engine.run()
        guard case .ready(let manifest, let assets) = outcome else { throw FetchError.paused("\(outcome)") }
        say("manifest version \(manifest.itemVersionID): \(manifest.assets.count) file(s), \(manifest.totalBytes) bytes, "
            + "\(manifest.assets.map(\.parts.count).reduce(0, +)) part(s)")
        for asset in assets { say("verified sha256 \(asset.sha256) length \(asset.length)") }

        let downloaded = Receipt(
            receiptID: CanonicalID.make(), queueEntryID: queueEntryID, itemID: itemID, itemVersionID: manifest.itemVersionID,
            state: .downloadedToPhone, occurredAt: Date())
        let firstAck = try await client.postReceipt(downloaded)
        say("receipt downloaded_to_phone -> entry state \(firstAck.entryState?.rawValue ?? "none (catalog download)")")
        let retried = try await client.postReceipt(downloaded)
        say("same receipt retried -> duplicate \(retried.duplicate)")

        // Stand-in for the importer: copy the verified files out.
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for (index, asset) in assets.enumerated() {
            let destination = out.appendingPathComponent("\(index)-\(asset.assetID)")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: asset.url, to: destination)
        }
        try? FileManager.default.removeItem(at: staging)
        say("simulated import: copied \(assets.count) verified file(s) to the output folder (the real importer is not part of this spike)")
        let imported = Receipt(
            receiptID: CanonicalID.make(), queueEntryID: queueEntryID, itemID: itemID, itemVersionID: manifest.itemVersionID,
            state: .importedIntoSylvia, occurredAt: Date())
        let importAck = try await client.postReceipt(imported)
        say("receipt imported_into_sylvia -> entry state \(importAck.entryState?.rawValue ?? "none (catalog download)")")
        say("done")
    }

    enum FetchError: Error, CustomStringConvertible {
        case unreachable
        case nothingQueued
        case noSuchTitle
        case noSuchEndpoint
        case paused(String)
        var description: String {
            switch self {
            case .unreachable: "no endpoint answered"
            case .noSuchEndpoint: "the pairing payload has no endpoint with the --only-host host"
            case .nothingQueued: "nothing was queued for this device in time"
            case .noSuchTitle: "no catalog item with that title"
            case .paused(let detail): "transfer did not finish: \(detail)"
            }
        }
    }

    @Sendable static func say(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("sylvia-fetch: \(message)\n\n\(usage)\n".utf8))
        exit(64)
    }
}
