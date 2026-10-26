import Foundation
import G05TestSupport
import SylviaAI
import Testing

/// App Transport Security probe (plan 14.3: an HTTP exception only for eligible local endpoints and only if the
/// minimum OS's ATS behaviour passes testing; never a global ATS disable). Each host app differs only in its ATS
/// keys; the same tests run hosted in each.
///
/// Every address is loopback or the machine's own LAN address on a closed port (on the simulator the Mac's, whose
/// interfaces it shares; on a device the phone's Wi-Fi address: `probeAddress`), except `plainHTTPToAPublicIPLiteral`
/// (a TEST-NET-1 documentation address that no host uses) and the device-only `plainHTTPToAnotherDeviceOnTheLAN`.
///
/// Apple documents that from iOS 17 ATS blocks plain-HTTP loads to IP addresses unless an exception applies;
/// NSAllowsLocalNetworking re-allows unqualified names, .local names and IP addresses; and individual IPs or
/// CIDR ranges can be listed in NSExceptionDomains.
@Suite("ATS probe", .serialized)
struct ATSProbeTests {
    enum Variant: String { case `default` = "default", localNetworking = "local_networking", cidrException = "cidr_exception" }
    static let variant = Variant(rawValue: Bundle.main.object(forInfoDictionaryKey: "G05ATSVariant") as? String ?? "")!

    static func load(_ url: URL, timeout: TimeInterval = 5) async -> Result<Int, URLError> {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        do {
            let (_, response) = try await URLSession(configuration: .ephemeral).data(for: request)
            return .success((response as? HTTPURLResponse)?.statusCode ?? -1)
        } catch let error as URLError {
            return .failure(error)
        } catch {
            return .failure(URLError(.unknown))
        }
    }

    static func isATSBlock(_ result: Result<Int, URLError>) -> Bool {
        if case .failure(let error) = result { return error.code == .appTransportSecurityRequiresSecureConnection }
        return false
    }

    @Test func variantIsKnown() {
        #expect([Variant.default, .localNetworking, .cidrException].contains(Self.variant))
        let ats = Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Any]
        #expect(ats?["NSAllowsArbitraryLoads"] == nil, "no global ATS disable in any variant")
    }

    /// A private IPv4 address (10/8, 172.16/12 or 192.168/16) of this machine and the interface that holds it.
    struct InterfaceAddress: Equatable {
        var interface: String
        var address: String
        /// The first two octets only, as the device checklist's records keep addresses.
        var masked: String { address.split(separator: ".").prefix(2).joined(separator: ".") + ".x.x" }
    }

    /// Every up, non-loopback IPv4 address of this machine in a private range, with its interface's name, in
    /// `getifaddrs` order. On the simulator these are the Mac's own interfaces (the simulator shares the host's).
    static func privateIPv4Addresses() -> [InterfaceAddress] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var found: [InterfaceAddress] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  (entry.ifa_flags & UInt32(IFF_UP)) != 0, (entry.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let text = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if EndpointPolicy.isEligibleLocalAddress(text), !text.hasPrefix("127."), !text.hasPrefix("169.254.") {
                found.append(InterfaceAddress(interface: String(cString: entry.ifa_name), address: text))
            }
        }
        return found
    }

    /// The iPhone's Wi-Fi interface; phone B's own log of the first device run names it (`interface: en0[802.11]`,
    /// `Docs/Stage0/evidence/G05-AI/device/step-01-ats.log`). On a device where en0 holds no private address the
    /// test stops at its precondition and its log lists the interfaces that do.
    static let wifiInterface = "en0"

    static var runsOnDevice: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }

    /// The address `plainHTTPToAPrivateLANAddress` loads, on a port with no listener: the machine's own address on its
    /// local network, so that a load ATS lets through is refused by the machine itself (URLError -1004, as on the
    /// simulator) and goes nowhere else.
    /// - Simulator: the first private address of any interface, as since the G0.5 run: the Mac's own LAN address.
    /// - Device: the Wi-Fi interface's (en0), and nothing else. A phone also has private IPv4 addresses on interfaces
    ///   that are not a local network: cellular (pdp_ip*), VPN and other tunnels (utun*, ipsec*). The first device run
    ///   took the first private address of any interface, 10.71.x.x, and its load went to iCloud Private Relay over
    ///   Wi-Fi and timed out (`Docs/Stage0/evidence/M0-DeviceFixes/ats/README.md`).
    /// nil when there is no such address: the test then reports an unmet precondition, never an ATS result.
    static func probeAddress(from candidates: [InterfaceAddress], onDevice: Bool) -> InterfaceAddress? {
        onDevice ? candidates.first(where: { $0.interface == wifiInterface }) : candidates.first
    }

    /// `probeAddress`'s rule on made-up interface lists. It runs everywhere; which addresses a phone's interfaces really
    /// hold, and what a load to its Wi-Fi address does, only a device run shows.
    @Test func onADeviceOnlyTheWiFiAddressIsProbed() {
        let cellular = InterfaceAddress(interface: "pdp_ip0", address: "10.0.0.2")
        let tunnel = InterfaceAddress(interface: "utun4", address: "10.8.0.2")
        let ipsec = InterfaceAddress(interface: "ipsec1", address: "172.16.0.2")
        let wifi = InterfaceAddress(interface: "en0", address: "192.168.0.20")
        let otherEthernet = InterfaceAddress(interface: "en2", address: "192.168.2.3")
        // Device: the Wi-Fi address, even when cellular, tunnel or other interfaces' addresses come first.
        #expect(Self.probeAddress(from: [cellular, tunnel, ipsec, wifi], onDevice: true) == wifi)
        #expect(Self.probeAddress(from: [otherEthernet, wifi], onDevice: true) == wifi)
        // Device, no Wi-Fi address: none, never a cellular, tunnel or other interface's address.
        #expect(Self.probeAddress(from: [cellular, tunnel, ipsec, otherEthernet], onDevice: true) == nil)
        #expect(Self.probeAddress(from: [], onDevice: true) == nil)
        // Simulator: unchanged, the first address whatever its interface.
        #expect(Self.probeAddress(from: [cellular, wifi], onDevice: false) == cellular)
        #expect(Self.probeAddress(from: [wifi, otherEthernet], onDevice: false) == wifi)
        #expect(Self.probeAddress(from: [], onDevice: false) == nil)
        #expect(InterfaceAddress(interface: "en0", address: "192.168.0.20").masked == "192.168.x.x")
    }

    @Test func plainHTTPToLoopbackPassesATSInEveryVariant() async throws {
        // Observed on the iOS 26.5 simulator: loopback IP literals are not subject to ATS's IP-address rule.
        let server = try await FakeHTTPServer { _ in .json(200, "{}") }
        let result = await Self.load(server.url("/v1/models"))
        #expect(try result.get() == 200)
        #expect(server.requests.count == 1)
    }

    @Test func plainHTTPToAPrivateLANAddress() async throws {
        let candidates = Self.privateIPv4Addresses()
        // What the address was chosen from, so the record shows which interfaces held private addresses.
        let listed = candidates.isEmpty ? "none" : candidates.map { "\($0.interface):\($0.masked)" }.joined(separator: ",")
        print("ATS-PROBE variant=\(Self.variant.rawValue) private-ipv4-interfaces=\(listed) rule=\(Self.runsOnDevice ? "device: \(Self.wifiInterface) (Wi-Fi) only" : "simulator: the first of any interface")")
        let chosen = Self.probeAddress(from: candidates, onDevice: Self.runsOnDevice)
        let precondition = Self.runsOnDevice
            ? "the phone needs a private IPv4 address (10/8, 172.16/12 or 192.168/16) on its Wi-Fi interface, \(Self.wifiInterface): join such a Wi-Fi network and run again"
            : "this Mac needs a private IPv4 address (10/8, 172.16/12 or 192.168/16) for the probe"
        if chosen == nil {
            print("ATS-PROBE variant=\(Self.variant.rawValue) private-ip=none precondition-not-met (ATS not probed; not an ATS result): \(precondition)")
        }
        let probe = try #require(chosen, "precondition not met, so ATS was not probed (not an ATS result): \(precondition)")
        // A port bound only on loopback, so nothing listens on the LAN address.
        let server = try await FakeHTTPServer { _ in .json(200, "{}") }
        let result = await Self.load(URL(string: "http://\(probe.address):\(server.port)/v1/models")!)
        let outcome = switch result {
        case .success(let status): "http \(status)"
        // The classified kind is what Sylvia would tell the user (device checklist step 2 reads it with Local
        // Network access turned off: expected local_network_permission_denied).
        case .failure(let error): "URLError \(error.code.rawValue) classified=\(ErrorClassifier.classify(error, host: "probe", bodyMayHaveBeenSent: false).kind.rawValue)"
        }
        print("ATS-PROBE variant=\(Self.variant.rawValue) private-ip=\(probe.masked) interface=\(probe.interface) result=\(outcome)")
        switch Self.variant {
        case .default:
            #if targetEnvironment(simulator)
            // Observed on the iOS 26.5 simulator (G0.5 evidence): the load is NOT blocked by ATS, contrary to
            // Apple's documentation for iOS 17+. Device behaviour is checked separately (device checklist step 1);
            // a simulator result is never taken as the device result.
            #expect(!Self.isATSBlock(result), "simulator behaviour changed; re-check the G0.5 ATS finding; got \(result)")
            #else
            // Apple's documented behaviour, kept as the device expectation so that a phone that does otherwise is
            // recorded as a failure of it. The first device run (iPhone 17 Pro, iOS 27.0.1) was not blocked, as on the
            // simulator: a timeout, not -1022 (Docs/Stage0/evidence/G05-AI/device/step-01-ats.txt).
            #expect(Self.isATSBlock(result), "documented iOS 17+ behaviour: ATS blocks cleartext to an IP literal without an exception; got \(result)")
            #endif
        case .localNetworking, .cidrException:
            #expect(!Self.isATSBlock(result), "the exception lets the load through ATS; got \(result)")
            if case .failure(let error) = result { #expect(error.code == .cannotConnectToHost, "refused locally; got \(error.code.rawValue)") }
        }
        #expect(server.requests.isEmpty)
    }

    /// TEST-NET-1 (RFC 5737): reserved for documentation and never assigned to a host, so a load that gets past ATS
    /// reaches no server (at most one connection attempt leaves the machine and is dropped). ATS treats it as a public
    /// IP literal. This is the case the shipping key decision needs: does `NSAllowsLocalNetworking` (or a CIDR
    /// exception) also let cleartext through to a public address? Sylvia's EndpointPolicy refuses it either way.
    static let publicIPLiteral = "192.0.2.1"

    @Test func plainHTTPToAPublicIPLiteral() async throws {
        let result = await Self.load(URL(string: "http://\(Self.publicIPLiteral)/v1/models")!, timeout: 3)
        let outcome = switch result {
        case .success(let status): "http \(status)"
        case .failure(let error): "URLError \(error.code.rawValue)"
        }
        print("ATS-PROBE variant=\(Self.variant.rawValue) public-ip=\(Self.publicIPLiteral) result=\(outcome) ats-blocked=\(Self.isATSBlock(result))")
        #expect((try? result.get()) == nil, "nothing answers at a TEST-NET-1 address; got \(result)")
        var config = ProviderConfig(kind: .openAICompatibleChat, displayName: "x", baseURL: URL(string: "http://\(Self.publicIPLiteral)/v1")!,
                                    model: "m", credential: nil)
        config.allowInsecureLocalHTTP = true
        #expect(throws: EndpointPolicyViolation.self, "Sylvia refuses cleartext to a public address whatever ATS allows") {
            try EndpointPolicy.assess(config)
        }
        switch Self.variant {
        case .default, .cidrException:
            #if targetEnvironment(simulator)
            Self.expectSimulatorObservation(result, blocked: Self.simulatorBlocksPublicIP[Self.variant]!)
            #else
            // Documented iOS 17+ behaviour; 192.0.2.1 is outside every CIDR exception.
            #expect(Self.isATSBlock(result), "ATS blocks cleartext to a public IP literal without a matching exception; got \(result)")
            #endif
        case .localNetworking:
            #if targetEnvironment(simulator)
            Self.expectSimulatorObservation(result, blocked: Self.simulatorBlocksPublicIP[Self.variant]!)
            #else
            // Not settled by Apple's documentation: recorded by device checklist step 1 for the key decision.
            #expect(Self.isATSBlock(result) || [.timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet]
                .contains((result.failureValue)?.code), "got \(result)")
            #endif
        }
    }

    /// What the iOS 26.5 simulator did in the G0.5 run (simulator-ats-keychain-probe.log). A change makes the test
    /// fail so the finding is re-checked; a simulator result is never taken as the device result.
    static let simulatorBlocksPublicIP: [Variant: Bool] = [.default: true, .localNetworking: true, .cidrException: true]

    static func expectSimulatorObservation(_ result: Result<Int, URLError>, blocked: Bool) {
        #expect(Self.isATSBlock(result) == blocked, "simulator ATS behaviour for a public IP literal changed (expected blocked=\(blocked)); got \(result)")
    }

    /// Device checklist step 2: Local Network privacy applies to other devices on the network, so this load goes to
    /// another device the person names (for example the Mac running `python3 -m http.server`). It runs only when
    /// `xcodebuild` passes TEST_RUNNER_G05_LAN_TARGET=<ip>:<port> and TEST_RUNNER_G05_EXPECT_LOCAL_NETWORK=allowed|denied.
    static let lanTarget = ProcessInfo.processInfo.environment["G05_LAN_TARGET"]
    static let expectLocalNetwork = ProcessInfo.processInfo.environment["G05_EXPECT_LOCAL_NETWORK"]

    @Test(.enabled(if: lanTarget != nil && expectLocalNetwork != nil, "device checklist step 2 only: needs G05_LAN_TARGET and G05_EXPECT_LOCAL_NETWORK"))
    func plainHTTPToAnotherDeviceOnTheLAN() async throws {
        let target = try #require(Self.lanTarget)
        let result = await Self.load(URL(string: "http://\(target)/")!)
        let classified = result.failureValue.map { ErrorClassifier.classify($0, host: "probe", bodyMayHaveBeenSent: false).kind.rawValue } ?? "-"
        let host = target.split(separator: ":").first.map(String.init) ?? target
        let masked = host.split(separator: ".").prefix(2).joined(separator: ".") + ".x.x"
        print("ATS-PROBE variant=\(Self.variant.rawValue) lan-target=\(masked) expect=\(Self.expectLocalNetwork ?? "") result=\(result.map { "http \($0)" }) classified=\(classified)")
        switch Self.expectLocalNetwork {
        case "denied":
            #expect(classified == FailureKind.localNetworkPermissionDenied.rawValue, "Local Network access is off: the message must say so, not \"offline\"; got \(result)")
        case "allowed":
            #expect((try? result.get()) != nil, "Local Network access is on and the target serves HTTP: the load must arrive; got \(result)")
        default:
            Issue.record("G05_EXPECT_LOCAL_NETWORK must be allowed or denied")
        }
    }

    @Test func plainHTTPToAQualifiedNameIsBlockedInEveryVariant() async {
        let result = await Self.load(URL(string: "http://sylvia-ats-probe.invalid/v1/models")!)
        #expect(Self.isATSBlock(result), "no variant allows cleartext to a qualified internet name; got \(result)")
    }

    @Test func plainHTTPToLocalhostName() async throws {
        let server = try await FakeHTTPServer { _ in .json(200, "{}") }
        let result = await Self.load(URL(string: "http://localhost:\(server.port)/v1/models")!)
        // Recorded for the report: whether the unqualified name "localhost" passes ATS in each variant.
        switch result {
        case .success(let status): #expect(status == 200)
        case .failure(let error): #expect(error.code == .appTransportSecurityRequiresSecureConnection || error.code == .cannotConnectToHost,
                                          "unexpected failure \(error.code.rawValue)")
        }
        print("ATS-PROBE variant=\(Self.variant.rawValue) localhost=\(result)")
    }

    @Test func sylviaPolicyStillGatesWhatATSAllows() async throws {
        // Even where ATS would allow an IP literal (local-networking variant), Sylvia's EndpointPolicy decides:
        // cleartext needs the opt-in and an eligible local address.
        let server = try await FakeHTTPServer { _ in .json(200, "{}") }
        var config = ProviderConfig(kind: .openAICompatibleChat, displayName: "x", baseURL: server.url("/v1"), model: "m", credential: nil)
        #expect(throws: EndpointPolicyViolation.self) { try EndpointPolicy.assess(config) }
        config.allowInsecureLocalHTTP = true
        #expect(throws: Never.self) { try EndpointPolicy.assess(config) }
        config.baseURL = URL(string: "http://8.8.8.8/v1")!
        #expect(throws: EndpointPolicyViolation.self) { try EndpointPolicy.assess(config) }
    }

    @Test func httpsToANonTLSServerIsClassifiedAsTLS() async throws {
        let server = try await FakeHTTPServer { _ in .json(200, "{}") }
        let config = ProviderConfig(kind: .openAICompatibleChat, displayName: "x", baseURL: URL(string: "https://127.0.0.1:\(server.port)/v1")!,
                                    model: "m", credential: nil)
        let report = await ConnectionTester(credentials: InMemoryCredentialStore(), transport: URLSessionTransport()).test(config)
        guard case .failed(let error) = report.outcome else { Issue.record("expected failure"); return }
        #expect(error.kind == .tls)
        #expect(server.requests.isEmpty)
    }
}

extension Result {
    var failureValue: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
