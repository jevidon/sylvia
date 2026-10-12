import CryptoKit
import Foundation
import NIOHTTP1
import Synchronization
import SylviaTransferCore

/// Maps requests to the Section 15.3 endpoints (Contracts/openapi/source-service.v1.yaml).
///
/// Rules applied to every request, before routing:
/// - the path is matched segment by segment against fixed routes; percent-encoding, empty segments,
///   `.` and `..` are refused; IDs must be canonical lowercase UUIDs; a path never reaches the file system;
/// - `/v<N>/...` with N != 1 gets 400 `unsupported_protocol_version` and an update message;
/// - a token in the query string (`access_token`, `token`, ...) is refused, never used;
/// - a request carrying `Origin` (a browser) is refused; no CORS header is ever sent;
/// - authentication is `Authorization: Bearer <token>` only; scopes are checked per endpoint.
final class Router: Sendable {
    let sourceID: String
    let capabilities: Capabilities
    let pairing: PairingAuthority
    let library: SourceLibrary
    let queue: OutboundQueue
    let preparationResponseLimit: Duration
    let faults: FaultPlan?
    let log: Mutex<[LoggedRequest]>

    init(
        sourceID: String, capabilities: Capabilities, pairing: PairingAuthority, library: SourceLibrary, queue: OutboundQueue,
        preparationResponseLimit: Duration, faults: FaultPlan?
    ) {
        self.sourceID = sourceID
        self.capabilities = capabilities
        self.pairing = pairing
        self.library = library
        self.queue = queue
        self.preparationResponseLimit = preparationResponseLimit
        self.faults = faults
        log = Mutex([])
    }

    static let forbiddenQueryNames: Set<String> = ["access_token", "token", "auth", "authorization", "bearer", "key", "secret"]

    func handle(_ request: HTTPRequest) async -> HTTPResponse {
        let (response, faultName) = await route(request)
        let path = request.uri.split(separator: "?", maxSplits: 1).first.map(String.init) ?? request.uri
        log.withLock {
            $0.append(LoggedRequest(
                method: request.method.rawValue, path: path, range: request.headers.first(name: "Range"),
                status: Int(response.status.code), fault: faultName))
        }
        return response
    }

    private func route(_ request: HTTPRequest) async -> (HTTPResponse, String?) {
        let parts = request.uri.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = String(parts[0])
        let query = parts.count > 1 ? String(parts[1]) : ""
        guard path.hasPrefix("/"), !path.contains("%"), !path.contains("//"), path.utf8.count <= 256 else {
            return (Self.error(.badRequest, code: "invalid_request", message: "The request path is not valid."), nil)
        }
        let segments = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if segments.contains(where: { $0 == "." || $0 == ".." || $0.isEmpty }) {
            return (Self.error(.badRequest, code: "invalid_request", message: "The request path is not valid."), nil)
        }
        guard let version = segments.first, version.hasPrefix("v"), let major = Int(version.dropFirst()) else {
            return (Self.error(.notFound, code: "not_found", message: "No such endpoint."), nil)
        }
        guard major == TransferProtocol.major else {
            return (Self.error(.badRequest, code: "unsupported_protocol_version",
                               message: "This Mac speaks transfer protocol version \(TransferProtocol.major). Update Sylvia on both devices."), nil)
        }
        let queryItems: [URLQueryItem]
        if query.isEmpty {
            queryItems = []
        } else if let items = URLComponents(string: "?" + query)?.queryItems {
            queryItems = items
        } else {
            return (Self.error(.badRequest, code: "invalid_request", message: "The query is not valid."), nil)
        }
        if queryItems.contains(where: { Self.forbiddenQueryNames.contains($0.name.lowercased()) }) {
            return (Self.error(.badRequest, code: "token_in_query_forbidden",
                               message: "Credentials are accepted only in the Authorization header."), nil)
        }
        if request.headers.contains(name: "Origin") {
            return (Self.error(.forbidden, code: "browser_origin_forbidden", message: "Browser access is not supported."), nil)
        }
        let rest = Array(segments.dropFirst())
        switch (request.method, rest.count, rest.first) {
        case (.GET, 1, "capabilities"):
            return (Self.json(.ok, capabilities), nil)
        case (.POST, 1, "pair"):
            return (await pair(request), nil)
        case (.GET, 1, "catalog"):
            return (await authenticated(request, scope: .catalog) { _ in await catalog(queryItems) }, nil)
        case (.GET, 3, "items") where rest[2] == "manifest":
            return (await authenticated(request, scope: .read) { _ in await manifest(itemID: rest[1], query: queryItems) }, nil)
        case (.GET, 3, "assets") where rest[2] == "content":
            var faultName: String?
            let response = await authenticated(request, scope: .download) { _ in
                let (response, fault) = await content(assetID: rest[1], request: request)
                faultName = fault
                return response
            }
            return (response, faultName)
        case (.GET, 1, "device-inbox"):
            return (await authenticated(request, scope: .catalog) { device in await inbox(device: device, query: queryItems) }, nil)
        case (.POST, 1, "receipts"):
            return (await authenticated(request, scope: .receipt) { device in await receipt(device: device, body: request.body) }, nil)
        case (.DELETE, 2, "pairings"):
            return (await authenticated(request, scope: nil) { device in await revoke(device: device, target: rest[1]) }, nil)
        case (_, 1, "capabilities"), (_, 1, "pair"), (_, 1, "catalog"), (_, 3, "items"), (_, 3, "assets"),
            (_, 1, "device-inbox"), (_, 1, "receipts"), (_, 2, "pairings"):
            var response = Self.error(.methodNotAllowed, code: "method_not_allowed", message: "Method not allowed.")
            response.headers.add(name: "Allow", value: Self.allowed(rest.first ?? ""))
            return (response, nil)
        default:
            return (Self.error(.notFound, code: "not_found", message: "No such endpoint."), nil)
        }
    }

    static func allowed(_ resource: String) -> String {
        switch resource {
        case "pair", "receipts": "POST"
        case "pairings": "DELETE"
        default: "GET"
        }
    }

    // MARK: Authentication

    private func authenticated(
        _ request: HTTPRequest, scope: Scope?, _ body: (PairedDevice) async -> HTTPResponse
    ) async -> HTTPResponse {
        let values = request.headers["Authorization"]
        guard values.count == 1, let value = values.first, value.hasPrefix("Bearer "), value.count > 7 else {
            var response = Self.error(.unauthorized, code: "unauthenticated", message: "Pair this device with the Mac first.")
            response.headers.add(name: "WWW-Authenticate", value: "Bearer realm=\"sylvia\"")
            return response
        }
        guard let device = await pairing.authenticate(token: String(value.dropFirst(7))) else {
            var response = Self.error(.unauthorized, code: "unauthenticated",
                                      message: "This device's pairing is not valid any more. Pair again.")
            response.headers.add(name: "WWW-Authenticate", value: "Bearer realm=\"sylvia\", error=\"invalid_token\"")
            return response
        }
        if let scope, !device.scopes.contains(scope) {
            return Self.error(.forbidden, code: "insufficient_scope", message: "This device may not do that.")
        }
        return await body(device)
    }

    // MARK: Endpoints

    private func pair(_ request: HTTPRequest) async -> HTTPResponse {
        guard request.headers.first(name: "Content-Type")?.lowercased().hasPrefix("application/json") == true,
            let body = try? TransferJSON.decode(PairRequest.self, from: Data(request.body))
        else { return Self.error(.badRequest, code: "invalid_request", message: "The pairing request is not valid.") }
        do {
            return Self.json(.ok, try await pairing.pair(body, remoteAddress: request.remoteAddress))
        } catch {
            switch error {
            case .invitationInvalid:
                return Self.error(.forbidden, code: "invitation_invalid", message: "This invitation is not valid.")
            case .invitationExpired:
                return Self.error(.forbidden, code: "invitation_expired", message: "This invitation expired. Create a new one on the Mac.")
            case .invitationUsed:
                return Self.error(.forbidden, code: "invitation_used", message: "This invitation was already used. Create a new one on the Mac.")
            case .sourceMismatch:
                return Self.error(.forbidden, code: "source_mismatch", message: "This invitation is for a different Mac.")
            case .denied:
                return Self.error(.forbidden, code: "pairing_denied", message: "The Mac user declined this device.")
            case .approvalTimeout:
                return Self.error(.forbidden, code: "approval_timeout", message: "Nobody approved the request on the Mac in time.")
            case .rateLimited(let seconds):
                var response = Self.error(.tooManyRequests, code: "rate_limited", message: "Too many pairing attempts. Try again later.",
                                          retryable: true, retryAfter: seconds)
                response.headers.add(name: "Retry-After", value: String(seconds))
                return response
            case .invalidRequest:
                return Self.error(.badRequest, code: "invalid_request", message: "The pairing request is not valid.")
            case .storageFailure:
                return Self.error(.internalServerError, code: "internal_error", message: "The Mac could not save the pairing.", retryable: true)
            }
        }
    }

    private func catalog(_ query: [URLQueryItem]) async -> HTTPResponse {
        guard let limit = Self.limit(query) else {
            return Self.error(.badRequest, code: "invalid_request", message: "limit must be 1 to \(TransferProtocol.maximumPageLimit).")
        }
        var after: String?
        if let cursor = query.first(where: { $0.name == "cursor" })?.value {
            guard let decoded = Self.decodeCursor(cursor), CanonicalID.isValid(decoded) else {
                return Self.error(.badRequest, code: "invalid_cursor", message: "The cursor is not valid.")
            }
            after = decoded
        }
        do {
            let page = try await library.catalog(after: after, limit: limit)
            return Self.json(.ok, CatalogPage(items: page.items, nextCursor: page.next.map(Self.encodeCursor)))
        } catch {
            return Self.error(.internalServerError, code: "internal_error", message: "The library could not be read.", retryable: true)
        }
    }

    private func manifest(itemID: String, query: [URLQueryItem]) async -> HTTPResponse {
        guard CanonicalID.isValid(itemID) else { return Self.error(.badRequest, code: "invalid_id", message: "The item ID is not valid.") }
        var partSize: Int64?
        if let text = query.first(where: { $0.name == "part_size" })?.value {
            guard let value = Int64(text), value >= capabilities.partSize.minimumBytes, value <= capabilities.partSize.maximumBytes,
                value % TransferProtocol.mebibyte == 0
            else { return Self.error(.badRequest, code: "invalid_part_size", message: "part_size must be a whole number of MiB within the advertised range.") }
            partSize = value
        }
        // Preparation (clone and hash) of a large item can take longer than a phone waits for a response.
        // It runs in its own task; if it is not done within the limit the phone is told to come back, and
        // the work continues (a later request joins it or finds the finished version).
        let library = self.library
        let sourceID = self.sourceID
        let size = partSize ?? capabilities.partSize.defaultBytes
        let work = Task { () async -> Result<TransferManifest, SourceLibrary.LibraryError> in
            do throws(SourceLibrary.LibraryError) {
                return .success(try await library.manifest(itemID: itemID, sourceID: sourceID, partSize: size))
            } catch {
                return .failure(error)
            }
        }
        guard let result = await FirstOf.value(of: work, within: preparationResponseLimit) else {
            let seconds = 2
            var response = Self.error(.serviceUnavailable, code: "preparing",
                                      message: "The Mac is preparing this item for transfer. Try again shortly.",
                                      retryable: true, retryAfter: seconds)
            response.headers.add(name: "Retry-After", value: String(seconds))
            return response
        }
        switch result {
        case .success(var manifest):
            if faults?.corruptManifestFullDigest == true {
                manifest.assets[0].sha256 = String(repeating: "0", count: 64)
                manifest.manifestDigest = manifest.computedDigest()
            }
            return Self.json(.ok, manifest)
        case .failure(let error):
            return Self.libraryError(error)
        }
    }

    private func content(assetID: String, request: HTTPRequest) async -> (HTTPResponse, String?) {
        guard CanonicalID.isValid(assetID) else {
            return (Self.error(.badRequest, code: "invalid_id", message: "The asset ID is not valid."), nil)
        }
        // RFC 9110 13.2.2: evaluate If-Match before Range.
        let ifMatch = request.headers["If-Match"]
        guard !ifMatch.isEmpty else {
            return (Self.error(HTTPResponseStatus(statusCode: 428), code: "precondition_required",
                               message: "Content requests must carry If-Match with the manifest's ETag."), nil)
        }
        guard ifMatch.count == 1, let tag = ifMatch.first, tag != "*", !tag.contains(","),
            ETag.isStrong(tag) || tag.hasPrefix("W/")
        else {
            return (Self.error(.badRequest, code: "invalid_precondition", message: "If-Match must be one entity tag."), nil)
        }
        let info: SourceLibrary.ServeInfo
        switch await library.serveInfo(assetID: assetID) {
        case .unknown:
            return (Self.error(.notFound, code: "not_found", message: "No such asset."), nil)
        case .noCurrentVersion:
            return (Self.preconditionFailed(currentETag: nil), nil)
        case .current(let current):
            info = current
        }
        guard ETag.strongMatch(tag, info.etag) else { return (Self.preconditionFailed(currentETag: info.etag), nil) }

        var range: ClosedRange<Int64>?
        let rangeHeaders = request.headers["Range"]
        if !rangeHeaders.isEmpty {
            guard rangeHeaders.count == 1 else {
                return (Self.error(.badRequest, code: "multiple_ranges_unsupported", message: "Request one byte range at a time."), nil)
            }
            switch RangeRequest.parse(rangeHeaders[0]) {
            case .multiple:
                return (Self.error(.badRequest, code: "multiple_ranges_unsupported", message: "Request one byte range at a time."), nil)
            case .invalid:
                return (Self.error(.badRequest, code: "invalid_range", message: "The Range header is not valid."), nil)
            case let parsed:
                guard let resolved = parsed.resolve(length: info.length) else {
                    var response = Self.error(.rangeNotSatisfiable, code: "range_not_satisfiable",
                                              message: "The requested range is outside the file. Fetch the manifest again.")
                    response.headers.add(name: "Content-Range", value: ContentRange.unsatisfied(length: info.length))
                    response.headers.add(name: "ETag", value: info.etag)
                    return (response, nil)
                }
                range = resolved
            }
        }

        let (fault, _) = faults?.fault(assetID: assetID, range: range) ?? (nil, 0)
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: info.mediaType)
        headers.add(name: "Accept-Ranges", value: "bytes")
        headers.add(name: "ETag", value: fault == .wrongETag ? ETag.forContentDigest(String(repeating: "f", count: 64)) : info.etag)
        if fault == .gzipEncoding { headers.add(name: "Content-Encoding", value: "gzip") }
        switch fault {
        case .preconditionFailed?:
            return (Self.preconditionFailed(currentETag: info.etag), "preconditionFailed")
        case .rangeNotSatisfiable?:
            var response = Self.error(.rangeNotSatisfiable, code: "range_not_satisfiable", message: "Injected 416.")
            response.headers.add(name: "Content-Range", value: ContentRange.unsatisfied(length: info.length))
            return (response, "rangeNotSatisfiable")
        case .ignoreRange?:
            return (HTTPResponse(status: .ok, headers: headers,
                                 body: .file(.init(descriptor: info.descriptor, range: 0...(info.length - 1), assetID: assetID, fault: nil))), "ignoreRange")
        default:
            break
        }
        guard var served = range else {
            return (HTTPResponse(status: .ok, headers: headers,
                                 body: .file(.init(descriptor: info.descriptor, range: 0...(info.length - 1), assetID: assetID, fault: fault))),
                    fault.map { "\($0)" })
        }
        if case .shortRange(let by)? = fault, served.upperBound - by >= served.lowerBound {
            served = served.lowerBound...(served.upperBound - by)
        }
        headers.add(name: "Content-Range", value: ContentRange.satisfied(served, length: info.length))
        return (HTTPResponse(status: .partialContent, headers: headers,
                             body: .file(.init(descriptor: info.descriptor, range: served, assetID: assetID, fault: fault))),
                fault.map { "\($0)" })
    }

    private func inbox(device: PairedDevice, query: [URLQueryItem]) async -> HTTPResponse {
        guard let limit = Self.limit(query) else {
            return Self.error(.badRequest, code: "invalid_request", message: "limit must be 1 to \(TransferProtocol.maximumPageLimit).")
        }
        var after = 0
        if let cursor = query.first(where: { $0.name == "cursor" })?.value {
            guard let decoded = Self.decodeCursor(cursor), decoded.hasPrefix("seq:"), let sequence = Int(decoded.dropFirst(4)), sequence >= 0 else {
                return Self.error(.badRequest, code: "invalid_cursor", message: "The cursor is not valid.")
            }
            after = sequence
        }
        do {
            let page = try await queue.inbox(deviceID: device.deviceID, afterSequence: after, limit: limit)
            var entries: [InboxEntry] = []
            for entry in page.entries {
                let summary = await library.summary(itemID: entry.itemID)
                var versionID = entry.itemVersionID
                // If the original changed since queueing, point the entry at the current version (or none yet).
                if let summary, summary.currentVersionID != versionID {
                    if let current = summary.currentVersionID { try? await queue.repoint(queueEntryID: entry.queueEntryID, to: current) }
                    versionID = summary.currentVersionID
                }
                entries.append(InboxEntry(
                    queueEntryID: entry.queueEntryID, itemID: entry.itemID, itemVersionID: versionID,
                    title: summary?.title ?? "Unavailable item", totalBytes: summary?.totalBytes ?? 0, queuedAt: entry.queuedAt,
                    state: entry.state))
            }
            return Self.json(.ok, DeviceInboxPage(entries: entries, nextCursor: page.nextSequence.map { Self.encodeCursor("seq:\($0)") }))
        } catch {
            return Self.error(.internalServerError, code: "internal_error", message: "The queue could not be read.", retryable: true)
        }
    }

    private func receipt(device: PairedDevice, body: [UInt8]) async -> HTTPResponse {
        guard let receipt = try? TransferJSON.decode(Receipt.self, from: Data(body)) else {
            return Self.error(.badRequest, code: "invalid_request", message: "The receipt is not valid.")
        }
        do {
            let ack = try await queue.apply(receipt, from: device.deviceID, bodySHA256: SHA256Hex.digest(Data(TransferJSON.encode(receipt))))
            return Self.json(.ok, ack)
        } catch let error as OutboundQueue.ReceiptError {
            switch error {
            case .conflict: return Self.error(.conflict, code: "receipt_conflict", message: "This receipt ID was used with different content.")
            case .unknownEntry: return Self.error(.notFound, code: "not_found", message: "No such queue entry for this device.")
            case .mismatch, .invalid: return Self.error(.badRequest, code: "invalid_request", message: "The receipt does not match the queue entry.")
            case .storageFailure: return Self.error(.internalServerError, code: "internal_error", message: "The Mac could not save the receipt.", retryable: true)
            }
        } catch {
            return Self.error(.badRequest, code: "invalid_request", message: "The receipt is not valid.")
        }
    }

    private func revoke(device: PairedDevice, target: String) async -> HTTPResponse {
        guard CanonicalID.isValid(target) else { return Self.error(.badRequest, code: "invalid_id", message: "The device ID is not valid.") }
        // A device may revoke only itself; revoking other devices is done by the owner on the Mac.
        guard target == device.deviceID else {
            return Self.error(.forbidden, code: "forbidden", message: "A device can only remove its own pairing.")
        }
        do {
            try await pairing.revoke(deviceID: target)
        } catch {
            return Self.error(.internalServerError, code: "internal_error", message: "The Mac could not save the change.", retryable: true)
        }
        return HTTPResponse(status: .noContent, headers: HTTPHeaders(), body: .empty)
    }

    // MARK: Helpers

    static func limit(_ query: [URLQueryItem]) -> Int? {
        guard let text = query.first(where: { $0.name == "limit" })?.value else { return TransferProtocol.defaultPageLimit }
        guard let value = Int(text), (1...TransferProtocol.maximumPageLimit).contains(value) else { return nil }
        return value
    }

    static func encodeCursor(_ value: String) -> String { Base64URL.encode(Array(value.utf8)) }
    static func decodeCursor(_ cursor: String) -> String? {
        guard cursor.utf8.count <= 256, let bytes = Base64URL.decode(cursor) else { return nil }
        return String(bytes: bytes, encoding: .utf8)
    }

    static func preconditionFailed(currentETag: String?) -> HTTPResponse {
        var response = error(.preconditionFailed, code: "precondition_failed",
                             message: "The file changed on the Mac. Fetch the manifest again.")
        if let currentETag { response.headers.add(name: "ETag", value: currentETag) }
        return response
    }

    static func libraryError(_ error: SourceLibrary.LibraryError) -> HTTPResponse {
        switch error {
        case .unknownItem: return self.error(.notFound, code: "not_found", message: "No such item.")
        case .sourceUnavailable:
            return self.error(.notFound, code: "source_unavailable", message: "The file is not available on the Mac right now.", retryable: true)
        case .sourceKeepsChanging:
            return self.error(.conflict, code: "source_changing", message: "The file is still changing on the Mac. Try again shortly.", retryable: true)
        case .emptyFile: return self.error(.conflict, code: "empty_file", message: "The file is empty.")
        case .tooLarge: return self.error(.conflict, code: "item_too_large", message: "The item has too many parts for this protocol version.")
        case .io: return self.error(.internalServerError, code: "internal_error", message: "The Mac could not prepare the file.", retryable: true)
        }
    }

    static func json<T: Encodable>(_ status: HTTPResponseStatus, _ value: T) -> HTTPResponse {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        let body = (try? TransferJSON.encode(value)).map { [UInt8]($0) } ?? []
        return HTTPResponse(status: status, headers: headers, body: .bytes(body))
    }

    static func error(
        _ status: HTTPResponseStatus, code: String, message: String, retryable: Bool = false, retryAfter: Int? = nil
    ) -> HTTPResponse {
        json(status, ErrorBody(code: code, message: message, retryable: retryable, retryAfterSeconds: retryAfter))
    }
}
