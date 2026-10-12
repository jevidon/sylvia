import Darwin
import Foundation

/// A tiny HTTP server on 127.0.0.1 with a kernel-assigned port that records every request it receives.
/// Test-only: it lets the safety tests prove whether rendering a publication reached the network.
final class LoopbackRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [String] = []
    private var listener: Int32 = -1
    private(set) var port: UInt16 = 0
    private var thread: Thread?

    var requests: [String] { lock.lock(); defer { lock.unlock() }; return _requests }

    func reset() { lock.lock(); _requests = []; lock.unlock() }

    func start() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw TestFailure(description: "socket() failed") }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0 // ephemeral
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0, listen(fd, 64) == 0 else { close(fd); throw TestFailure(description: "bind/listen failed") }
        var out = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &out) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) } }
        port = UInt16(bigEndian: out.sin_port)
        listener = fd
        let t = Thread { [weak self] in self?.acceptLoop(fd) }
        t.name = "LoopbackRecorder"
        thread = t
        t.start()
    }

    func stop() {
        if listener >= 0 {
            shutdown(listener, SHUT_RDWR)
            close(listener)
            listener = -1
        }
    }

    deinit { stop() }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 { return }
            // One thread per connection, with a receive timeout, so a client that never finishes its request (a media
            // element, a WebSocket) cannot hold up the requests behind it.
            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var noSigPipe: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            let t = Thread { [weak self] in self?.serve(client) }
            t.name = "LoopbackRecorder.client"
            t.start()
        }
    }

    private func serve(_ client: Int32) {
        var buffer = [UInt8](repeating: 0, count: 8192)
        var received = Data()
        while received.count < 65536 {
            let n = read(client, &buffer, buffer.count)
            if n <= 0 { break }
            received.append(buffer, count: n)
            if received.range(of: Data("\r\n\r\n".utf8)) != nil { break }
        }
        let head = String(decoding: received, as: UTF8.self)
        let requestLine = head.components(separatedBy: "\r\n").first.flatMap { $0.isEmpty ? nil : $0 } ?? "<connection without a request line>"
        lock.lock(); _requests.append(requestLine); lock.unlock()
        let path = requestLine.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
        let (type, body): (String, String) = path.hasSuffix(".js")
            ? ("text/javascript", "window.__sylviaRemoteJS = true;")
            : path.hasSuffix(".css") ? ("text/css", "body { background: red; }") : ("text/plain", "recorded")
        let response = "HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        _ = response.withCString { write(client, $0, strlen($0)) }
        close(client)
    }
}

/// Physical memory footprint of this process (what iOS uses for jetsam decisions).
func physFootprint() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    return kr == KERN_SUCCESS ? info.phys_footprint : 0
}
