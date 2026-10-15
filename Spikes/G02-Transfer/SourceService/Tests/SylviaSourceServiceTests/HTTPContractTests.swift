import Foundation
import Testing
@_spi(Testing) import SylviaSourceService
@_spi(Testing) import SylviaTransferClient
import SylviaTransferCore

/// The Section 15.3 HTTP contract against the running source. Environment: host (macOS), real TLS.
/// Responses are also captured to Docs/Stage0/evidence/G02-Transfer/captured/ and validated against
/// the JSON Schemas by the CI drop-in.
@Suite("HTTP contract (15.3)", .serialized)
struct HTTPContractTests {
    static let assetBytes = Harness.bytes(seed: 9, count: 3 * Harness.mib + 1234)

    func setUp() async throws -> (Harness, SourceClient, String) {
        let harness = try await Harness.make(files: [
            "walden.epub": Self.assetBytes,
            "Meditations/01 Book One.mp3": Harness.bytes(seed: 10, count: 2 * Harness.mib),
            "Meditations/02 Book Two.mp3": Harness.bytes(seed: 11, count: 1000),
            "empty.txt": [],
            ".hidden.epub": [1, 2, 3],
        ])
        let (client, _, token) = try await harness.pairDevice()
        return (harness, client, token)
    }

    static func capture(_ name: String, _ data: Data) {
        Evidence.write("captured/\(name).json", String(decoding: data, as: UTF8.self))
    }

    static func code(_ response: SourceClient.RawResponse) -> String? {
        (try? TransferJSON.decode(ErrorBody.self, from: response.body))?.error.code
    }

    @Test func capabilitiesAreUnauthenticatedAndCarryNoLibraryData() async throws {
        let (harness, _, _) = try await setUp()
        defer { await harness.cleanUp() }
        let response = try await harness.unauthenticatedClient().raw(method: "GET", pathAndQuery: "/v1/capabilities")
        #expect(response.status == 200)
        let text = String(decoding: response.body, as: UTF8.self)
        #expect(!text.contains("walden") && !text.contains("Meditations") && !text.contains("Test Mac"))
        let capabilities = try TransferJSON.decode(Capabilities.self, from: response.body)
        #expect(capabilities.sourceID == harness.service.sourceID)
        #expect(capabilities.partSize.defaultBytes == TransferProtocol.mebibyte)
        #expect(capabilities.negotiatedPartSize() == Optional(TransferProtocol.defaultPartSize))
        Self.capture("capabilities", response.body)
    }

    @Test func catalogListsTopLevelFilesAndFoldersWithStablePagination() async throws {
        let (harness, client, token) = try await setUp()
        defer { await harness.cleanUp() }
        let all = try await client.catalog()
        #expect(Set(all.items.map(\.title)) == ["walden", "Meditations", "empty"])  // hidden file skipped
        let group = try #require(all.items.first { $0.title == "Meditations" })
        #expect(group.kind == .group && group.assetCount == 2 && group.preparationState == .notPrepared)
        Self.capture("catalog-page", try TransferJSON.encode(all))

        let first = try await client.catalog(limit: 2)
        #expect(first.items.count == 2)
        let cursor = try #require(first.nextCursor)
        // A new file arriving between pages does not shift or repeat the remaining entries.
        try Data([1, 2, 3]).write(to: harness.root.appendingPathComponent("zzz-new.pdf"))
        try await Task.sleep(for: .milliseconds(2100))
        let second = try await client.catalog(cursor: cursor, limit: 2)
        let seen = first.items.map(\.itemID) + second.items.map(\.itemID)
        #expect(Set(seen).count == seen.count)
        #expect(seen == seen.sorted())
        let bad = try await harness.unauthenticatedClient().raw(
            method: "GET", pathAndQuery: "/v1/catalog?cursor=not-a-cursor", headers: ["Authorization": "Bearer \(token)"])
        #expect(bad.status == 400 && Self.code(bad) == "invalid_cursor")
        let tooMany = try await harness.unauthenticatedClient().raw(
            method: "GET", pathAndQuery: "/v1/catalog?limit=201", headers: ["Authorization": "Bearer \(token)"])
        #expect(tooMany.status == 400)
    }

    @Test func manifestDescribesAnImmutableVersionAndNegotiatesPartSize() async throws {
        let (harness, client, token) = try await setUp()
        defer { await harness.cleanUp() }
        let itemID = try await harness.itemID(titled: "walden")
        let manifest = try await client.manifest(itemID: itemID)  // validated by ManifestValidator inside
        #expect(manifest.assets.count == 1)
        #expect(manifest.assets[0].sha256 == SHA256Hex.digest(Self.assetBytes))
        #expect(manifest.assets[0].parts.count == 4 && manifest.assets[0].partSize == TransferProtocol.mebibyte)
        #expect(manifest.assets[0].etag == "\"sha256-\(manifest.assets[0].sha256)\"")
        #expect(await harness.service.library.snapshotsWereCloned(itemID: itemID) == true)  // APFS clone, not a copy
        let again = try await client.manifest(itemID: itemID)
        #expect(again.itemVersionID == manifest.itemVersionID)  // unchanged original: same version
        let twoMiB = try await client.manifest(itemID: itemID, partSize: 2 * TransferProtocol.mebibyte)
        #expect(twoMiB.assets[0].parts.count == 2 && twoMiB.itemVersionID == manifest.itemVersionID)
        let raw = try await harness.unauthenticatedClient().raw(
            method: "GET", pathAndQuery: "/v1/items/\(itemID)/manifest", headers: ["Authorization": "Bearer \(token)"])
        Self.capture("transfer-manifest", raw.body)
        for bad in ["1048577", "524288", "0", "x", "134217728"] {
            let response = try await harness.unauthenticatedClient().raw(
                method: "GET", pathAndQuery: "/v1/items/\(itemID)/manifest?part_size=\(bad)", headers: ["Authorization": "Bearer \(token)"])
            #expect(response.status == 400 && Self.code(response) == "invalid_part_size", "\(bad)")
        }
        let groupID = try await harness.itemID(titled: "Meditations")
        let group = try await client.manifest(itemID: groupID)
        #expect(group.grouping.kind == .group)
        #expect(group.assets.map(\.displayName) == ["01 Book One.mp3", "02 Book Two.mp3"])
        #expect(group.assets.map(\.mediaType) == ["audio/mpeg", "audio/mpeg"])
        let emptyID = try await harness.itemID(titled: "empty")
        await #expect(throws: ClientError.http(status: 409, code: "empty_file")) { _ = try await client.manifest(itemID: emptyID) }
    }

    @Test func rangeRequestsFollowRFC9110Exactly() async throws {
        let (harness, client, token) = try await setUp()
        defer { await harness.cleanUp() }
        let itemID = try await harness.itemID(titled: "walden")
        let asset = try await client.manifest(itemID: itemID).assets[0]
        let raw = harness.unauthenticatedClient()
        let path = "/v1/assets/\(asset.assetID)/content"
        func get(_ headers: [String: String]) async throws -> SourceClient.RawResponse {
            var all = headers
            all["Authorization"] = "Bearer \(token)"
            return try await raw.raw(method: "GET", pathAndQuery: path, headers: all)
        }
        let length = Int64(Self.assetBytes.count)
        var transcript = ["host (macOS): GET \(path) on the in-process source; asset length \(length)"]
        func note(_ label: String, _ response: SourceClient.RawResponse) {
            transcript.append("\(label): \(response.status) Content-Range=\(response.header("Content-Range") ?? "-") "
                + "Content-Length=\(response.header("Content-Length") ?? "-") ETag-matches=\(response.header("ETag") == asset.etag) "
                + "Content-Encoding=\(response.header("Content-Encoding") ?? "-") Cache-Control=\(response.header("Cache-Control") ?? "-") "
                + "body=\(response.body.count)B code=\(Self.code(response) ?? "-")")
        }

        let partial = try await get(["Range": "bytes=100-199", "If-Match": asset.etag])
        note("bytes=100-199", partial)
        #expect(partial.status == 206)
        #expect(partial.header("Content-Range") == "bytes 100-199/\(length)")
        #expect(partial.header("Content-Length") == "100")
        #expect(partial.header("ETag") == asset.etag)
        #expect(partial.header("Accept-Ranges") == "bytes")
        #expect(partial.header("Content-Encoding") == nil)
        #expect(partial.header("Cache-Control")?.contains("no-transform") == true)
        #expect(partial.header("Access-Control-Allow-Origin") == nil)
        #expect(partial.body == Data(Self.assetBytes[100...199]))

        let open = try await get(["Range": "bytes=\(length - 10)-", "If-Match": asset.etag])
        note("bytes=\(length - 10)-", open)
        #expect(open.status == 206 && open.body == Data(Self.assetBytes.suffix(10)))
        let suffix = try await get(["Range": "bytes=-5", "If-Match": asset.etag])
        note("bytes=-5", suffix)
        #expect(suffix.status == 206 && suffix.header("Content-Range") == "bytes \(length - 5)-\(length - 1)/\(length)")
        let clamped = try await get(["Range": "bytes=\(length - 3)-\(length + 1000)", "If-Match": asset.etag])
        note("past end (clamped)", clamped)
        #expect(clamped.status == 206 && clamped.body.count == 3)

        let unsatisfiable = try await get(["Range": "bytes=\(length)-", "If-Match": asset.etag])
        note("bytes=\(length)- (416)", unsatisfiable)
        #expect(unsatisfiable.status == 416 && unsatisfiable.header("Content-Range") == "bytes */\(length)")
        let multiple = try await get(["Range": "bytes=0-1,5-6", "If-Match": asset.etag])
        note("two ranges", multiple)
        #expect(multiple.status == 400 && Self.code(multiple) == "multiple_ranges_unsupported")
        let invalid = try await get(["Range": "bytes=abc", "If-Match": asset.etag])
        note("invalid Range", invalid)
        #expect(invalid.status == 400 && Self.code(invalid) == "invalid_range")

        let missingIfMatch = try await get(["Range": "bytes=0-1"])
        note("no If-Match", missingIfMatch)
        #expect(missingIfMatch.status == 428 && Self.code(missingIfMatch) == "precondition_required")
        let star = try await get(["Range": "bytes=0-1", "If-Match": "*"])
        #expect(star.status == 400 && Self.code(star) == "invalid_precondition")
        let weak = try await get(["Range": "bytes=0-1", "If-Match": "W/" + asset.etag])
        note("weak If-Match", weak)
        #expect(weak.status == 412)
        let stale = try await get(["Range": "bytes=0-1", "If-Match": ETag.forContentDigest(String(repeating: "a", count: 64))])
        note("stale If-Match", stale)
        #expect(stale.status == 412 && Self.code(stale) == "precondition_failed")
        Self.capture("error-precondition-failed", stale.body)

        let whole = try await get(["If-Match": asset.etag])
        note("no Range (200)", whole)
        #expect(whole.status == 200 && whole.header("Content-Length") == String(length) && whole.body == Data(Self.assetBytes))
        Evidence.write("range-semantics.txt", transcript.joined(separator: "\n") + "\n")
    }

    @Test func hostileRequestsNeverReachTheFileSystem() async throws {
        let (harness, _, token) = try await setUp()
        defer { await harness.cleanUp() }
        let raw = harness.unauthenticatedClient()
        let auth = ["Authorization": "Bearer \(token)"]
        let cases: [(String, Int, String)] = [
            ("/v1/items/..%2F..%2Fetc%2Fpasswd/manifest", 400, "invalid_request"),
            ("/v1/assets/%2e%2e/content", 400, "invalid_request"),
            ("/v1/items/ABCDEF00-0000-4000-8000-00000000000A/manifest", 400, "invalid_id"),
            ("/v1/items/walden.epub/manifest", 400, "invalid_id"),
            ("/v1/assets/\(CanonicalID.make())/content", 404, "not_found"),
            ("/v1/items/\(CanonicalID.make())/manifest", 404, "not_found"),
            ("/v1//catalog", 400, "invalid_request"),
            ("/v2/catalog", 400, "unsupported_protocol_version"),
            ("/capabilities", 404, "not_found"),
            ("/v1/files/etc/passwd", 404, "not_found"),
        ]
        var transcript = ["host (macOS): hostile request corpus against the in-process source"]
        for (path, status, code) in cases {
            var headers = auth
            if path.contains("/content") { headers["If-Match"] = ETag.forContentDigest(String(repeating: "a", count: 64)) }
            let response = try await raw.raw(method: "GET", pathAndQuery: path, headers: headers)
            transcript.append("\(path) -> \(response.status) \(Self.code(response) ?? "-")")
            #expect(response.status == status && Self.code(response) == code, "\(path)")
        }
        let version = try await raw.raw(method: "GET", pathAndQuery: "/v2/capabilities")
        #expect(try TransferJSON.decode(ErrorBody.self, from: version.body).error.message.contains("Update Sylvia"))
        let browser = try await raw.raw(method: "GET", pathAndQuery: "/v1/catalog", headers: auth.merging(["Origin": "https://evil.example"]) { $1 })
        transcript.append("Origin header -> \(browser.status) \(Self.code(browser) ?? "-")")
        #expect(browser.status == 403 && Self.code(browser) == "browser_origin_forbidden")
        let options = try await raw.raw(method: "OPTIONS", pathAndQuery: "/v1/catalog", headers: ["Origin": "https://evil.example", "Access-Control-Request-Method": "GET"])
        transcript.append("OPTIONS preflight -> \(options.status), Access-Control-Allow-Origin=\(options.header("Access-Control-Allow-Origin") ?? "absent")")
        #expect(options.header("Access-Control-Allow-Origin") == nil)
        let wrongMethod = try await raw.raw(method: "PUT", pathAndQuery: "/v1/catalog", headers: auth)
        #expect(wrongMethod.status == 405 && wrongMethod.header("Allow") == "GET")
        let big = try await raw.raw(method: "POST", pathAndQuery: "/v1/receipts", headers: auth.merging(["Content-Type": "application/json"]) { $1 },
                                    body: Data(repeating: 0x20, count: 70_000))
        transcript.append("70 KB receipt body -> \(big.status) \(Self.code(big) ?? "-")")
        #expect(big.status == 413)
        Self.capture("error-unsupported-version", version.body)
        Evidence.write("hostile-requests.txt", transcript.joined(separator: "\n") + "\n")
        // Every request above was answered from the index; the source folder is untouched.
        #expect(try FileManager.default.contentsOfDirectory(atPath: harness.root.path).sorted()
                == [".hidden.epub", "Meditations", "empty.txt", "walden.epub"])
    }

    @Test func refusesWildcardBindUnlessExplicit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("g02-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        var configuration = SourceServiceConfiguration(roots: [directory], stateDirectory: directory.appendingPathComponent("state"))
        configuration.bindAddresses = ["0.0.0.0"]
        await #expect(throws: ServiceError.wildcardBindRefused("0.0.0.0")) {
            _ = try await SourceService.start(configuration: configuration, identityStore: EphemeralIdentityStore(), approver: ScriptedApprover())
        }
    }
}
