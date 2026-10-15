import Foundation
import G05TestSupport
import SylviaAI
import Testing

/// App Transport Security probe (plan 14.3: an HTTP exception only for eligible local endpoints and only if the
/// minimum OS's ATS behaviour passes testing; never a global ATS disable). Each host app differs only in its ATS
/// keys; the same tests run hosted in each.
///
/// Every address is loopback or this Mac's own LAN address on a closed port, except `plainHTTPToAPublicIPLiteral`
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

    /// This Mac's own private IPv4 address (the simulator shares the host's interfaces). A load to it on a port
    /// with no listener is refused by the local kernel if ATS lets it through, so nothing leaves the machine.
    static func hostPrivateIPv4() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  (entry.ifa_flags & UInt32(IFF_UP)) != 0, (entry.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let text = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if EndpointPolicy.isEligibleLocalAddress(text), !text.hasPrefix("127."), !text.hasPrefix("169.254.") { return text }
        }
        return nil
    }

    @Test func plainHTTPToLoopbackPassesATSInEveryVariant() async throws {
        // Observed on the iOS 26.5 simulator: loopback IP literals are not subject to ATS's IP-address rule.
        let server = try await FakeHTTPServer { _ in .json(200, "{}") }
        let result = await Self.load(server.url("/v1/models"))
        #expect(try result.get() == 200)
        #expect(server.requests.count == 1)
    }

    @Test func plainHTTPToAPrivateLANAddress() async throws {
        let address = try #require(Self.hostPrivateIPv4(), "this Mac needs a private IPv4 address (10/8, 172.16/12 or 192.168/16) for the probe")
        // A port bound only on loopback, so nothing listens on the LAN address.
        let server = try await FakeHTTPServer { _ in .json(200, "{}") }
        let result = await Self.load(URL(string: "http://\(address):\(server.port)/v1/models")!)
        let masked = address.split(separator: ".").prefix(2).joined(separator: ".") + ".x.x"
        let outcome = switch result {
        case .success(let status): "http \(status)"
        // The classified kind is what Sylvia would tell the user (device checklist step 2 reads it with Local
        // Network access turned off: expected local_network_permission_denied).
        case .failure(let error): "URLError \(error.code.rawValue) classified=\(ErrorClassifier.classify(error, host: "probe", bodyMayHaveBeenSent: false).kind.rawValue)"
        }
        print("ATS-PROBE variant=\(Self.variant.rawValue) private-ip=\(masked) result=\(outcome)")
        switch Self.variant {
        case .default:
            #if targetEnvironment(simulator)
            // Observed on the iOS 26.5 simulator (G0.5 evidence): the load is NOT blocked by ATS, contrary to
            // Apple's documentation for iOS 17+. Device behaviour is checked separately (device checklist step 1);
            // a simulator result is never taken as the device result.
            #expect(!Self.isATSBlock(result), "simulator behaviour changed; re-check the G0.5 ATS finding; got \(result)")
            #else
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
