import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOSSL
import Synchronization
import SylviaTransferCore

/// One parsed request. The body is bounded by `TransferProtocol.maximumRequestBodyBytes`.
struct HTTPRequest: Sendable {
    var method: HTTPMethod
    var uri: String
    var headers: HTTPHeaders
    var body: [UInt8]
    var remoteAddress: String
}

/// An open read-only descriptor of an immutable snapshot, opened by the library inside its actor right
/// after it confirmed the version is current. Closed when the last response holding it is done, so a
/// version invalidated (and its snapshot unlinked) while a response is streaming keeps serving the bytes
/// that were current when the request was checked, and never anything else.
final class SnapshotDescriptor: Sendable {
    let fd: Int32
    init(fd: Int32) { self.fd = fd }
    deinit { close(fd) }
}

/// Counters for tests and evidence. `decryptedBytes` counts application bytes the TLS layer decrypted
/// from clients: zero after a refused handshake proves no request (and so no secret) reached the server.
final class ServerCounters: Sendable {
    struct Values: Sendable {
        var connections = 0
        var requests = 0
        var decryptedBytes = 0
        var refusedWhileStopping = 0
    }

    private let values = Mutex(Values())
    func update(_ change: (inout Values) -> Void) { values.withLock { change(&$0) } }
    var current: Values { values.withLock { $0 } }
}

/// Whether a connection's request is being handled (a pairing approval can take up to its timeout, a
/// first manifest request hashes the whole file). The idle limit applies only outside that phase.
final class ConnectionActivity: Sendable {
    private let handling = Mutex(false)
    var isHandling: Bool { handling.withLock { $0 } }
    func setHandling(_ value: Bool) { handling.withLock { $0 = value } }
}

struct HTTPResponse: Sendable {
    struct FileBody: Sendable {
        var descriptor: SnapshotDescriptor
        var range: ClosedRange<Int64>
        var assetID: String
        var fault: ContentFault?
    }

    enum Body: Sendable {
        case empty
        case bytes([UInt8])
        case file(FileBody)
    }

    var status: HTTPResponseStatus
    var headers: HTTPHeaders
    var body: Body
}

/// HTTP/1.1 over TLS on SwiftNIO and NIOSSL (ADR-0009). Explicit bind addresses only. Bodies are
/// streamed from the immutable snapshot in 256 KiB chunks with NIO back-pressure (`outbound.write`
/// suspends while the socket is not writable), so memory does not grow with the asset size.
final class HTTPServer: Sendable {
    typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    static let chunkSize = 262_144

    typealias Connection = (activity: ConnectionActivity, channel: NIOAsyncChannel<HTTPServerRequestPart, HTTPServerResponsePart>)

    /// The accept path (child channel initializers, on the event loops) and stop() share this state under
    /// one lock, so a connection accepted while stop() runs is either in the set stop() closes and waits
    /// for, or is closed unserved by its initializer.
    ///
    /// Why the initializer starts the serving task itself (review finding R1-01): a channel wrapped with
    /// `NIOAsyncChannel(wrappingChannelSynchronously:)` traps the process when it is released before
    /// `executeThenClose` runs ("Deinited NIOAsyncWriter without calling finish()"; the writer is created
    /// with `finishOnDeinit: false` and its deinit is a `preconditionFailure`, also in release builds).
    /// Handing wrapped channels to an accept loop through the listener's async sequence could release
    /// them unserved: NIO drops elements whose initializer completes after the listener's stream has
    /// finished, and elements still buffered when the accept loop ends. Here the wrapped channel moves
    /// straight into a new unstructured task whose first action is `executeThenClose`; that task is
    /// never cancelled before it gets there, so every wrapped channel's writer is finished.
    final class Lifecycle: Sendable {
        struct OpenConnection: Sendable {
            var channel: any Channel
            var task: Task<Void, Never>
        }

        struct State: Sendable {
            var stopped = false
            var connections: [ObjectIdentifier: OpenConnection] = [:]
        }

        let state = Mutex(State())
    }

    let group: MultiThreadedEventLoopGroup
    let port: Int
    let boundAddresses: [String]
    let counters: ServerCounters
    private let serverChannels: [any Channel]
    private let lifecycle: Lifecycle

    private init(
        group: MultiThreadedEventLoopGroup, port: Int, boundAddresses: [String], counters: ServerCounters,
        serverChannels: [any Channel], lifecycle: Lifecycle
    ) {
        self.group = group
        self.port = port
        self.boundAddresses = boundAddresses
        self.counters = counters
        self.serverChannels = serverChannels
        self.lifecycle = lifecycle
    }

    /// Connections the server is serving right now (for tests).
    var openConnectionCount: Int { lifecycle.state.withLock { $0.connections.count } }

    static func makeTLSConfiguration(identity: SourceIdentity) throws -> TLSConfiguration {
        let certificate = try NIOSSLCertificate(bytes: identity.certificateDER, format: .der)
        let key = try NIOSSLPrivateKey(bytes: Array(identity.privateKey.pemRepresentation.utf8), format: .pem)
        var configuration = TLSConfiguration.makeServerConfiguration(certificateChain: [.certificate(certificate)], privateKey: .privateKey(key))
        configuration.minimumTLSVersion = .tlsv12
        configuration.maximumTLSVersion = .tlsv13
        // TLS 1.2 fallback: forward-secret AEAD suites for an ECDSA certificate only.
        configuration.cipherSuites = "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305"
        configuration.applicationProtocols = ["http/1.1"]
        configuration.certificateVerification = .none  // clients authenticate with bearer tokens, not certificates
        return configuration
    }

    static func start(
        addresses: [String], port requestedPort: Int, tls: TLSConfiguration, idleTimeout: TimeAmount, faults: FaultPlan?,
        handler: @escaping Handler
    ) async throws -> HTTPServer {
        guard !addresses.isEmpty else { throw ServiceError.noBindAddress }
        let context = try NIOSSLContext(configuration: tls)
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        let counters = ServerCounters()
        let lifecycle = Lifecycle()
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 64)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(.socketOption(.tcp_nodelay), value: 1)
            .childChannelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try Self.accept(
                        channel, lifecycle: lifecycle, context: context, counters: counters, idleTimeout: idleTimeout,
                        faults: faults, handler: handler)
                }
            }
        var channels: [any Channel] = []
        var port = requestedPort
        do {
            for address in addresses {
                let bound: EventLoopFuture<any Channel> = bootstrap.bind(host: address, port: port)
                let channel = try await bound.get()
                if port == 0 { port = channel.localAddress?.port ?? 0 }
                channels.append(channel)
            }
        } catch {
            for channel in channels { try? await channel.close() }
            try? await group.shutdownGracefully()
            throw error
        }
        return HTTPServer(
            group: group, port: port, boundAddresses: addresses, counters: counters, serverChannels: channels,
            lifecycle: lifecycle)
    }

    /// Child channel initializer, on the connection's event loop. Either refuses the connection (the server
    /// is stopping) without ever wrapping it, or wraps it and starts the task that serves it in one
    /// critical section, so stop() sees every served connection (see `Lifecycle`).
    private static func accept(
        _ channel: any Channel, lifecycle: Lifecycle, context: NIOSSLContext, counters: ServerCounters,
        idleTimeout: TimeAmount, faults: FaultPlan?, handler: @escaping Handler
    ) throws {
        counters.update { $0.connections += 1 }
        let refuse = {
            counters.update { $0.refusedWhileStopping += 1 }
            channel.close(promise: nil)
        }
        if lifecycle.state.withLock({ $0.stopped }) {
            refuse()
            return
        }
        // A connection that neither sends nor receives for `idleTimeout` (a stalled TLS handshake, an idle
        // keep-alive, a client that stopped reading) is closed, except while its request is being handled.
        let activity = ConnectionActivity()
        let pipeline = channel.pipeline.syncOperations
        try pipeline.addHandler(IdleStateHandler(allTimeout: idleTimeout))
        try pipeline.addHandler(CloseOnIdleHandler(activity: activity))
        try pipeline.addHandler(NIOSSLServerHandler(context: context))
        try pipeline.addHandler(DecryptedByteCounter(counters: counters))
        try pipeline.configureHTTPServerPipeline(withErrorHandling: true)
        let key = ObjectIdentifier(channel)
        try lifecycle.state.withLock { state throws in
            guard !state.stopped else {
                refuse()
                return
            }
            let wrapped = try NIOAsyncChannel<HTTPServerRequestPart, HTTPServerResponsePart>(
                wrappingChannelSynchronously: channel)
            // From here on nothing may throw: the wrapped channel must reach executeThenClose in serve().
            let task = Task {
                await Self.serve((activity: activity, channel: wrapped), counters: counters, faults: faults, handler: handler)
                _ = lifecycle.state.withLock { $0.connections.removeValue(forKey: key) }
            }
            state.connections[key] = Lifecycle.OpenConnection(channel: channel, task: task)
        }
    }

    /// Stops listening and closes every connection, then shuts the event loops down. Idempotent: a second
    /// call returns at once (closing channels on an event loop group that has already shut down would
    /// never complete).
    ///
    /// Order matters: the listening sockets close first (no new connections; a connection whose
    /// initializer runs after stop() began is closed without being served), then every open connection is
    /// closed and its serving task given up to `drainLimit` to finish, and only then do the event loops
    /// shut down. Shutting the loops down under live connections made NIO report "Cannot schedule tasks on
    /// an EventLoop that has already shut down" (a future NIO version turns that into a crash).
    func stop(drainLimit: Duration = .seconds(5)) async {
        let open: [Lifecycle.OpenConnection]? = lifecycle.state.withLock { state in
            if state.stopped { return nil }
            state.stopped = true
            return Array(state.connections.values)
        }
        guard let open else { return }
        for channel in serverChannels { try? await channel.close() }
        for connection in open { try? await connection.channel.close() }
        let tasks = open.map(\.task)
        // A handler can be waiting on something that ignores cancellation (a pairing approval prompt);
        // after the drain limit the loops shut down regardless. Every task is already inside
        // executeThenClose, so cancelling it cannot leave a wrapped channel unfinished.
        await withTaskGroup(of: Void.self) { waiters in
            waiters.addTask {
                for task in tasks { await task.value }
            }
            waiters.addTask {
                try? await Task.sleep(for: drainLimit)
                for task in tasks { task.cancel() }
            }
            _ = await waiters.next()
            waiters.cancelAll()
        }
        try? await group.shutdownGracefully()
    }

    private static func serve(_ accepted: Connection, counters: ServerCounters, faults: FaultPlan?, handler: Handler) async {
        let (activity, connection) = accepted
        let remote = connection.channel.remoteAddress?.ipAddress ?? "unknown"
        do {
            try await connection.executeThenClose { inbound, outbound in
                var head: HTTPRequestHead?
                var body: [UInt8] = []
                var tooLarge = false
                for try await part in inbound {
                    switch part {
                    case .head(let requestHead):
                        head = requestHead
                        body = []
                        let declared = requestHead.headers.first(name: "Content-Length").flatMap(Int.init) ?? 0
                        tooLarge = declared > TransferProtocol.maximumRequestBodyBytes
                    case .body(var buffer):
                        if body.count + buffer.readableBytes > TransferProtocol.maximumRequestBodyBytes {
                            tooLarge = true
                        } else if let bytes = buffer.readBytes(length: buffer.readableBytes) {
                            body.append(contentsOf: bytes)
                        }
                    case .end:
                        guard let requestHead = head else { return }
                        counters.update { $0.requests += 1 }
                        let response: HTTPResponse
                        if tooLarge {
                            response = Router.error(.payloadTooLarge, code: "payload_too_large", message: "The request body is too large.")
                        } else {
                            activity.setHandling(true)
                            response = await handler(HTTPRequest(
                                method: requestHead.method, uri: requestHead.uri, headers: requestHead.headers, body: body,
                                remoteAddress: remote))
                            activity.setHandling(false)
                        }
                        let keepAlive = requestHead.isKeepAlive && !tooLarge && faults?.closeAfterEachResponse != true
                        let completed = try await write(
                            response, keepAlive: keepAlive, version: requestHead.version, outbound: outbound,
                            channel: connection.channel, faults: faults)
                        if !completed || !keepAlive { return }
                        head = nil
                    }
                }
            }
        } catch {
            // Handshake refused by the client (pin mismatch), peer reset, or an injected drop.
        }
    }

    /// Returns false when the connection was dropped on purpose (fault injection).
    private static func write(
        _ response: HTTPResponse, keepAlive: Bool, version: HTTPVersion,
        outbound: NIOAsyncChannelOutboundWriter<HTTPServerResponsePart>, channel: any Channel, faults: FaultPlan?
    ) async throws -> Bool {
        var headers = response.headers
        headers.replaceOrAdd(name: "Cache-Control", value: "no-store, no-transform")
        headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
        headers.replaceOrAdd(name: "Connection", value: keepAlive ? "keep-alive" : "close")
        switch response.body {
        case .empty:
            headers.replaceOrAdd(name: "Content-Length", value: "0")
            try await outbound.write(.head(HTTPResponseHead(version: version, status: response.status, headers: headers)))
            try await outbound.write(.end(nil))
            return true
        case .bytes(let bytes):
            headers.replaceOrAdd(name: "Content-Length", value: String(bytes.count))
            try await outbound.write(.head(HTTPResponseHead(version: version, status: response.status, headers: headers)))
            if !bytes.isEmpty { try await outbound.write(.body(.byteBuffer(ByteBuffer(bytes: bytes)))) }
            try await outbound.write(.end(nil))
            return true
        case .file(let file):
            let length = file.range.upperBound - file.range.lowerBound + 1
            headers.replaceOrAdd(name: "Content-Length", value: String(length))
            try await outbound.write(.head(HTTPResponseHead(version: version, status: response.status, headers: headers)))
            let descriptor = file.descriptor.fd
            var sent: Int64 = 0
            let dropLimit: Int64? = if case .dropAfter(let bytes) = file.fault { bytes } else { nil }
            while sent < length {
                if let dropLimit, sent >= dropLimit {
                    channel.close(promise: nil)
                    return false
                }
                var want = Int(min(Int64(Self.chunkSize), length - sent))
                if let dropLimit { want = Int(min(Int64(want), dropLimit - sent)) }
                let offset = file.range.lowerBound + sent
                var buffer = try await NIOThreadPool.singleton.runIfActive { [want] in
                    var buffer = ByteBufferAllocator().buffer(capacity: want)
                    let read = buffer.writeWithUnsafeMutableBytes(minimumWritableBytes: want) { pointer in
                        max(0, pread(descriptor, pointer.baseAddress, want, off_t(offset)))
                    }
                    return read == want ? buffer : ByteBuffer()
                }
                guard buffer.readableBytes == want else {
                    channel.close(promise: nil)
                    return false
                }
                if case .corruptByte(let at) = file.fault, at >= sent, at < sent + Int64(want) {
                    let index = buffer.readerIndex + Int(at - sent)
                    let byte = buffer.getInteger(at: index, as: UInt8.self) ?? 0
                    buffer.setInteger(byte ^ 0xFF, at: index)
                }
                try await outbound.write(.body(.byteBuffer(buffer)))
                sent += Int64(want)
                if let progress = faults?.bodyProgress.withLock({ $0 }) {
                    await progress(file.assetID, file.range.lowerBound, sent)
                }
            }
            try await outbound.write(.end(nil))
            return true
        }
    }
}

/// Closes the connection when `IdleStateHandler` reports inactivity, unless a request is being handled
/// (the handler is bounded by its own limits, such as the pairing approval timeout).
final class CloseOnIdleHandler: ChannelInboundHandler {
    typealias InboundIn = NIOAny
    let activity: ConnectionActivity

    init(activity: ConnectionActivity) { self.activity = activity }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is IdleStateHandler.IdleStateEvent {
            if !activity.isHandling { context.close(promise: nil) }
        } else {
            context.fireUserInboundEventTriggered(event)
        }
    }
}

/// Counts decrypted application bytes (placed right after the TLS handler) and passes them on unchanged.
final class DecryptedByteCounter: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    let counters: ServerCounters

    init(counters: ServerCounters) { self.counters = counters }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let count = unwrapInboundIn(data).readableBytes
        counters.update { $0.decryptedBytes += count }
        context.fireChannelRead(data)
    }
}

public enum ServiceError: Error, Equatable, Sendable {
    case noBindAddress
    case wildcardBindRefused(String)
    case invalidConfiguration(String)
}
