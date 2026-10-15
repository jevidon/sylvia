import Foundation
import NIOCore
import SylviaTransferCore

/// Configuration of the Mac source service.
public struct SourceServiceConfiguration: Sendable {
    /// User-selected folders. Items come only from these.
    public var roots: [URL]
    /// Index, paired devices (token hashes), outbound queue and snapshots.
    public var stateDirectory: URL
    /// Explicit interfaces to bind (plan 16.3). Loopback by default; LAN or Tailscale addresses must be
    /// named. The wildcard addresses are refused unless `allowAllInterfaces` is set.
    public var bindAddresses: [String] = ["127.0.0.1"]
    public var allowAllInterfaces = false
    /// 0 picks an ephemeral port (tests); every bind address uses the same port.
    public var port = 0
    /// Extra host names for the pairing payload (for example a Tailscale MagicDNS name).
    public var advertisedHosts: [String] = []
    public var sourceName = "Sylvia source"
    public var partSizes = Capabilities.PartSizes(
        defaultBytes: TransferProtocol.defaultPartSize, minimumBytes: TransferProtocol.minimumPartSize,
        maximumBytes: TransferProtocol.maximumPartSize)
    public var pairingLimits = PairingAuthority.Limits()
    public var advertiseBonjour = false
    /// Connections idle in both directions for this long are closed.
    public var idleTimeout: Duration = .seconds(60)
    /// A manifest request waits at most this long for preparation (clone and hash); after that it gets
    /// 503 `preparing` with Retry-After while preparation continues, so the phone's request never times out.
    public var preparationResponseLimit: Duration = .seconds(10)
    public var now: @Sendable () -> Date = { Date() }

    public init(roots: [URL], stateDirectory: URL) {
        self.roots = roots
        self.stateDirectory = stateDirectory
    }
}

/// The Mac source service: TLS identity, pairing, library, queue, HTTP server and Bonjour.
public final class SourceService: Sendable {
    public let identity: SourceIdentity
    public let configuration: SourceServiceConfiguration
    public let pairing: PairingAuthority
    public let library: SourceLibrary
    public let queue: OutboundQueue
    public let port: Int
    let server: HTTPServer
    let router: Router
    let bonjour: BonjourAdvertiser?
    /// DNS-SD registration result (0 when advertised, nil when not requested).
    public let bonjourStatus: Int32?

    public var sourceID: String { identity.sourceID }
    /// The fingerprint people compare: the SPKI SHA-256 in uppercase groups of four (plan 15.2).
    public var fingerprint: String { identity.pin.displayFingerprint }
    public var pin: SPKIPin { identity.pin }

    /// Endpoints for pairing payloads: each bound address (loopback included only when it is the only
    /// one) plus any advertised host names, all on the bound port.
    public var endpoints: [PairingPayload.Endpoint] {
        var hosts = configuration.bindAddresses.filter { !["0.0.0.0", "::"].contains($0) }
        let nonLoopback = hosts.filter { $0 != "127.0.0.1" && $0 != "::1" }
        if !nonLoopback.isEmpty { hosts = nonLoopback }
        hosts += configuration.advertisedHosts
        return Array(hosts.prefix(PairingPayload.maximumEndpoints)).map { PairingPayload.Endpoint(host: $0, port: port) }
    }

    public static func start(
        configuration: SourceServiceConfiguration, identityStore: any IdentityStore, approver: any PairingApprover
    ) async throws -> SourceService {
        try await start(configuration: configuration, identityStore: identityStore, approver: approver, faults: nil)
    }

    @_spi(Testing)
    public static func start(
        configuration: SourceServiceConfiguration, identityStore: any IdentityStore, approver: any PairingApprover,
        faults: FaultPlan?
    ) async throws -> SourceService {
        for address in configuration.bindAddresses where ["0.0.0.0", "::", "*"].contains(address) && !configuration.allowAllInterfaces {
            throw ServiceError.wildcardBindRefused(address)
        }
        guard !configuration.roots.isEmpty else { throw ServiceError.invalidConfiguration("no source folder") }
        let state = configuration.stateDirectory
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let (identity, identityCreated) = try identityStore.loadOrCreate(now: configuration.now())
        let pairing = try PairingAuthority(
            sourceID: identity.sourceID, pin: identity.pin, limits: configuration.pairingLimits, approver: approver,
            devicesURL: state.appendingPathComponent("devices.json"), now: configuration.now)
        // A new key means every earlier pairing was made with a key that no longer exists: void its tokens,
        // so a phone can only come back through an explicit new pairing (plan 15.2).
        if identityCreated { try await pairing.revokeAll() }
        let library = try SourceLibrary(
            roots: configuration.roots, stateDirectory: state, defaultPartSize: configuration.partSizes.defaultBytes, now: configuration.now)
        try await library.scan()
        let queue = try OutboundQueue(stateURL: state.appendingPathComponent("queue.json"), now: configuration.now)
        let capabilities = Capabilities(sourceID: identity.sourceID, partSize: configuration.partSizes)
        let router = Router(
            sourceID: identity.sourceID, capabilities: capabilities, pairing: pairing, library: library, queue: queue,
            preparationResponseLimit: configuration.preparationResponseLimit, faults: faults)
        let server = try await HTTPServer.start(
            addresses: configuration.bindAddresses, port: configuration.port,
            tls: HTTPServer.makeTLSConfiguration(identity: identity),
            idleTimeout: .nanoseconds(Int64(configuration.idleTimeout.components.seconds) * 1_000_000_000
                + configuration.idleTimeout.components.attoseconds / 1_000_000_000),
            faults: faults
        ) { request in
            await router.handle(request)
        }
        var bonjour: BonjourAdvertiser?
        var bonjourStatus: Int32?
        if configuration.advertiseBonjour {
            let advertiser = BonjourAdvertiser()
            bonjourStatus = advertiser.start(
                name: configuration.sourceName, port: server.port, sourceID: identity.sourceID, protocolMajor: TransferProtocol.major,
                localOnly: configuration.bindAddresses.allSatisfy { ["127.0.0.1", "::1"].contains($0) })
            bonjour = advertiser
        }
        return SourceService(
            identity: identity, configuration: configuration, pairing: pairing, library: library, queue: queue,
            server: server, router: router, bonjour: bonjour, bonjourStatus: bonjourStatus)
    }

    private init(
        identity: SourceIdentity, configuration: SourceServiceConfiguration, pairing: PairingAuthority, library: SourceLibrary,
        queue: OutboundQueue, server: HTTPServer, router: Router, bonjour: BonjourAdvertiser?, bonjourStatus: Int32?
    ) {
        self.identity = identity
        self.configuration = configuration
        self.pairing = pairing
        self.library = library
        self.queue = queue
        self.server = server
        self.router = router
        self.bonjour = bonjour
        self.bonjourStatus = bonjourStatus
        port = server.port
    }

    /// Issues a single-use invitation for this source's endpoints.
    public func issueInvitation() async -> PairingPayload {
        await pairing.issueInvitation(sourceName: configuration.sourceName, endpoints: endpoints, spki: identity.pin)
    }

    /// "Send to device": prepares the item (immutable snapshot) and queues it durably.
    public func send(itemID: String, toDevice deviceID: String) async throws -> OutboundQueue.Entry {
        let versionID = try await library.prepare(itemID: itemID)
        return try await queue.enqueue(itemID: itemID, itemVersionID: versionID, deviceID: deviceID)
    }

    /// Owner revocation on the Mac.
    @discardableResult
    public func revoke(deviceID: String) async throws -> Bool { try await pairing.revoke(deviceID: deviceID) }

    /// Stops serving immediately (plan 16.3).
    public func stop() async {
        bonjour?.stop()
        await server.stop()
    }

    @_spi(Testing) public var requestLog: [LoggedRequest] { router.log.withLock { $0 } }
    @_spi(Testing) public var connectionCount: Int { server.counters.current.connections }
    @_spi(Testing) public var requestCount: Int { server.counters.current.requests }
    /// Connections whose initializer ran after stop() began; closed without being served.
    @_spi(Testing) public var connectionsRefusedWhileStopping: Int { server.counters.current.refusedWhileStopping }
    /// Connections being served right now (zero once stop() has returned).
    @_spi(Testing) public var openConnectionCount: Int { server.openConnectionCount }
    /// Application bytes decrypted from clients, all connections together.
    @_spi(Testing) public var decryptedBytesReceived: Int { server.counters.current.decryptedBytes }
}
