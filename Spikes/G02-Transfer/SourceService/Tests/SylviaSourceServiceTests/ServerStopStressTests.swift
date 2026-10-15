import Darwin
import Foundation
import Synchronization
import Testing
@_spi(Testing) import SylviaSourceService
@_spi(Testing) import SylviaTransferClient
import SylviaTransferCore

/// Review finding R1-01: stopping the source while phones connect must never crash it (plan 16.3, "stop
/// serving immediately"). Before the fix, a connection wrapped for async use but never served (accepted as
/// the listener closed, or still buffered in the accept sequence) trapped the whole process in NIO
/// ("Deinited NIOAsyncWriter without calling finish()").
///
/// Environment: host (macOS), in-process source on 127.0.0.1, real TLS. Each iteration starts a source,
/// lets pinned TLS clients (a new URLSession, and so a new connection, per request) and raw TCP
/// connections that stall the handshake hit it in a tight loop, stops it at a varying moment while they
/// keep connecting, and checks that every served connection was closed and waited for. A trap ends the
/// test process, so reaching the end is the result.
@Suite("Mac source: stop while clients connect (16.3, R1-01)", .serialized)
struct ServerStopStressTests {
    static let iterations = 200

    struct Totals {
        var connections = 0
        var refusedWhileStopping = 0
        var requests = 0
        var iterationsWithRefusals = 0
    }

    /// Opens a TCP connection and holds it (an unfinished TLS handshake) for a few milliseconds.
    static func holdRawConnection(port: Int) async {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        try? await Task.sleep(for: .milliseconds(connected == 0 ? 3 : 1))
    }

    @Test func stoppingWhileClientsConnectNeverTrapsAndLeavesNoConnectionOpen() async throws {
        var totals = Totals()
        let started = ContinuousClock.now
        for iteration in 0..<Self.iterations {
            let harness = try await Harness.make(files: ["a.epub": Harness.bytes(seed: 7, count: 2000)])
            let service = harness.service
            let running = Mutex(true)
            let base = harness.baseURL
            let pin = service.pin
            let sourceID = service.sourceID
            let port = service.port
            await withTaskGroup(of: Void.self) { clients in
                for _ in 0..<3 {
                    clients.addTask {
                        while running.withLock({ $0 }) {
                            let client = SourceClient(baseURL: base, pin: pin, sourceID: sourceID, token: nil, timeout: 2)
                            _ = try? await client.capabilities()
                        }
                    }
                }
                for _ in 0..<2 {
                    clients.addTask {
                        while running.withLock({ $0 }) { await Self.holdRawConnection(port: port) }
                    }
                }
                // Stop at a different moment each time, while every client keeps connecting.
                try? await Task.sleep(for: .milliseconds(2 + iteration % 25))
                await service.stop()
                #expect(service.openConnectionCount == 0, "iteration \(iteration): a served connection outlived stop()")
                try? await Task.sleep(for: .milliseconds(5))
                running.withLock { $0 = false }
            }
            totals.connections += service.connectionCount
            totals.requests += service.requestCount
            totals.refusedWhileStopping += service.connectionsRefusedWhileStopping
            if service.connectionsRefusedWhileStopping > 0 { totals.iterationsWithRefusals += 1 }
            await harness.cleanUp()
        }
        let seconds = (ContinuousClock.now - started).components.seconds
        // The test only proves something if connections were really arriving while the source stopped.
        #expect(totals.requests > Self.iterations)
        #expect(totals.connections > 2 * Self.iterations)
        Evidence.write("review/stop-while-connecting.log", """
            environment: host (macOS), in-process source on 127.0.0.1, real TLS; swift test --filter ServerStopStressTests
            iterations: \(Self.iterations) (source started, 3 pinned TLS clients with a new connection per request and 2 raw TCP
              connections stalling the handshake in tight loops, source stopped after 2-26 ms while they kept connecting)
            connections accepted by the kernel and initialized: \(totals.connections)
            requests answered before the stops: \(totals.requests)
            connections whose initializer ran after stop() began (closed unserved): \(totals.refusedWhileStopping), in \(totals.iterationsWithRefusals) iterations
            served connections still open after stop() returned: 0 in every iteration (asserted)
            process trapped: no (the test process reached this line); duration: \(seconds) s

            """)
    }
}
