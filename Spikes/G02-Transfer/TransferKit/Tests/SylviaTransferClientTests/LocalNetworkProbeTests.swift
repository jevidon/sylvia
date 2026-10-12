import Darwin
import Foundation
import Testing
import SylviaTransferClient
import SylviaTransferCore

/// Review finding R2-03: telling a denied local network permission apart from an unreachable Mac.
/// Environment: host (macOS), loopback only. The command-line test process is not subject to local network
/// privacy, so `.denied` cannot occur here; it is a device checklist step (4, 18). These tests run the probe's
/// other answers for real and the classification around it.
@Suite("Local network permission check (R2-03)")
struct LocalNetworkProbeTests {
    /// A loopback TCP socket; listening or not.
    final class LoopbackSocket {
        let fd: Int32
        let port: Int

        init(listening: Bool) throws {
            let descriptor = socket(AF_INET, SOCK_STREAM, 0)
            try #require(descriptor >= 0)
            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET)
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            try #require(bound == 0)
            if listening { try #require(listen(descriptor, 4) == 0) }
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            _ = withUnsafeMutablePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
            }
            fd = descriptor
            port = Int(UInt16(bigEndian: address.sin_port))
        }

        deinit { close(fd) }
    }

    @Test func aListeningMacIsNotADenial() async throws {
        let socket = try LoopbackSocket(listening: true)
        #expect(await LocalNetworkProbe.check(.init(host: "127.0.0.1", port: socket.port)) == .notDenied)
    }

    @Test func aRefusedConnectionIsNotADenial() async throws {
        // A port that was free a moment ago and that nothing holds now: connections are refused (RST). (A socket
        // that is bound but not listening is not used: macOS drops the SYN and the connection only times out.)
        let port = try LoopbackSocket(listening: false).port
        #expect(await LocalNetworkProbe.check(.init(host: "127.0.0.1", port: port)) == .notDenied)
        #expect(await LocalNetworkProbe.anyDenied([.init(host: "127.0.0.1", port: port)]) == false)
    }

    @Test func onlyNetworkFailuresAreReclassified() async {
        let endpoints = [PairingPayload.Endpoint(host: "192.168.1.20", port: 4443)]
        let denied: @Sendable ([PairingPayload.Endpoint]) async -> Bool = { _ in true }
        let allowed: @Sendable ([PairingPayload.Endpoint]) async -> Bool = { _ in false }
        for error in [ClientError.unreachable, .timedOut, .dnsFailure, .transport(code: -1009)] {
            #expect(await error.classifyingLocalNetwork(endpoints: endpoints, isDenied: denied) == .localNetworkDenied)
            #expect(await error.classifyingLocalNetwork(endpoints: endpoints, isDenied: allowed) == error)
        }
        // A pin mismatch, an HTTP answer or a TLS failure means the network worked: never a permission problem.
        for error in [ClientError.pinMismatch, .http(status: 401, code: "unauthorized"), .tlsFailure, .cancelled] {
            #expect(await error.classifyingLocalNetwork(endpoints: endpoints, isDenied: denied) == error)
        }
        #expect(await ClientError.unreachable.classifyingLocalNetwork(endpoints: [], isDenied: denied) == .unreachable)
        #expect(TransferEngine.pauseReason(for: .localNetworkDenied) == .localNetworkDenied)
        #expect(PauseReason.localNetworkDenied.nextStep.contains("Settings > Privacy & Security > Local Network"))
    }
}
