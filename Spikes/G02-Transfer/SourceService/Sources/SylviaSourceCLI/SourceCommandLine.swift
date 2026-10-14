import Darwin
import Foundation
import Synchronization
@_spi(Testing) import SylviaSourceService
import SylviaTransferCore

/// `sylvia-source`: a command-line Mac source for manual and simulator tests (G0.2 deliverable 6).
/// `sylvia-test-source` is the same program with the test-only options listed in `testUsage` (G0.2 part 2).
///
/// Serves the given folders over TLS on explicit addresses, prints a single-use pairing payload (code
/// and link), asks on the terminal before pairing a phone, and accepts a few commands on stdin. It is a
/// Stage 0 harness, not the companion app: no UI, no start-at-login, no privileged helper.
///
/// The pairing code is printed to the terminal because showing it is how it reaches the phone; this
/// program never writes it (or any token) to a file or log. Standard output can be redirected by whoever starts
/// it, so the code and link lines start with "pairing code:" and "pairing link:" for redaction, and the optional
/// QR code (`--qr`) is drawn only on the controlling terminal.
public enum SourceCommandLine {
    static let usage = """
        usage: sylvia-source --root DIR [--root DIR ...] [options]

          --root DIR              a folder to share (repeatable); top-level files are items, top-level folders are groups
          --state DIR             index, paired devices (token hashes), queue and snapshots
                                  (default ~/Library/Application Support/com.jevidon.sylvia.spike.source)
          --bind ADDR             an address to listen on (repeatable; default 127.0.0.1). 0.0.0.0 and :: are refused.
          --lan                   also listen on the IPv4 address of each active Wi-Fi/Ethernet interface (en*)
          --port N                port for every bind address (default 0: pick a free port)
          --advertise-host NAME   extra endpoint for the pairing payload, e.g. a Tailscale MagicDNS name (repeatable)
          --name NAME             source name shown on the phone (default: this Mac's name)
          --bonjour               advertise _sylvia-src._tcp (local-only when bound to loopback only)
          --ephemeral-identity    keep the TLS key in memory only (scripted runs); default stores it in the Keychain
          --invitation-minutes N  invitation lifetime (default 10)
          --part-size-mib N       default part size (default 16; 1 to 64)
          --qr                    also draw each pairing link as a QR code, on this terminal only (/dev/tty; never on
                                  standard output, so redirected output and logs never hold it); needs a terminal
                                  at least 90 columns wide, more with more addresses (the source prints the width)

        commands on stdin:
          invite                  print a new single-use pairing code
          items                   list items: "item <item-id> <state> <title>"
          devices                 list paired devices
          send <item-id> <device-id>   queue an item for a device ("Queued on Mac")
          queue                   list queue entries and their acknowledgements
          revoke <device-id>      revoke a device
          quit                    stop serving and exit
        """

    static let testUsage = """

        test-only options (sylvia-test-source; never in sylvia-source or the companion):
          --test-auto-approve           approve every pairing request without asking (prints each one)
          --test-code-file PATH         write pairing codes to PATH (mode 0600) instead of printing them
          --test-invitations N          number of single-use codes to write (default 1)
          --test-ready-file PATH        write source id, fingerprint, port and endpoints as JSON when ready
          --test-corrupt-part N         flip one byte in the first response for part N (part-size offsets) of every asset
          --test-throttle-kib N         send content bodies at about N KiB/s per response
          --test-close-connections      answer every request with Connection: close (a new TLS handshake each time)
          --test-serve-until-killed     ignore end of input; serve until SIGTERM or SIGINT
          --test-log-requests           print each request as "request <time> <method> <path> range=<r> -> <status>" (IDs only)
          --test-send-on-pair TITLE     with --test-auto-approve: queue the item TITLE for every newly paired device
                                        (as the "send" command would), so a phone test finds it in /v1/device-inbox
        """

    public static func main(testHooks: Bool) async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let options: Options
        do {
            options = try Options.parse(arguments, allowTestOptions: testHooks)
        } catch {
            FileHandle.standardError.write(Data("\(error)\n\n\(usage)\(testHooks ? testUsage : "")\n".utf8))
            exit(64)
        }
        do {
            try await run(options)
        } catch {
            FileHandle.standardError.write(Data("sylvia-source: \(error)\n".utf8))
            exit(1)
        }
    }

    static func run(_ options: Options) async throws {
        let console = Console()
        var configuration = SourceServiceConfiguration(roots: options.roots, stateDirectory: options.state)
        configuration.bindAddresses = options.bind
        configuration.port = options.port
        configuration.advertisedHosts = options.advertisedHosts
        configuration.sourceName = options.name
        configuration.advertiseBonjour = options.bonjour
        configuration.pairingLimits.invitationLifetime = TimeInterval(options.invitationMinutes * 60)
        configuration.partSizes = .init(
            defaultBytes: Int64(options.partSizeMiB) * TransferProtocol.mebibyte, minimumBytes: TransferProtocol.minimumPartSize,
            maximumBytes: TransferProtocol.maximumPartSize)
        let identityStore: any IdentityStore =
            // An unsigned command-line tool has no keychain access group, so it may fall back to the login
            // keychain; it prints which one it used ("identity key:" below). The signed companion must not.
            options.ephemeralIdentity
                ? EphemeralIdentityStore() : KeychainIdentityStore(stateDirectory: options.state, policy: .allowLoginKeychainFallback)
        let faults = options.test.makeFaultPlan(partSizeBytes: Int64(options.partSizeMiB) * TransferProtocol.mebibyte)
        let autoApprover = options.test.autoApprove ? AutoApprover(console: console) : nil
        let approver: any PairingApprover = autoApprover ?? console
        let service = try await SourceService.start(
            configuration: configuration, identityStore: identityStore, approver: approver, faults: faults)
        if let title = options.test.sendOnPairTitle, let autoApprover {
            autoApprover.afterApproval.withLock { $0 = { deviceID in Self.sendOnPair(title: title, deviceID: deviceID, service, console) } }
        }
        if options.test.isActive {
            console.say("TEST SOURCE: fault injection and test hooks active (\(options.test.summary)); not a production configuration")
        }

        let backend = (identityStore as? KeychainIdentityStore)?.lastBackend?.rawValue ?? "memory only (--ephemeral-identity)"
        console.say("Sylvia source (G0.2 spike), protocol \(TransferProtocol.version)")
        console.say("source id: \(service.sourceID)")
        console.say("source name: \(options.name)")
        console.say("fingerprint: \(service.fingerprint)")
        console.say("identity key: \(backend)")
        console.say("listening: \(options.bind.map { "\($0):\(service.port)" }.joined(separator: " "))")
        console.say("endpoints in pairing payload: \(service.endpoints.map { "\($0.urlHost):\($0.port)" }.joined(separator: " "))")
        if let status = service.bonjourStatus {
            console.say(status == 0 ? "bonjour: advertising \(BonjourAdvertiser.serviceType)" : "bonjour: registration failed (\(status))")
        }
        console.say("shared folders: \(options.roots.count)")
        if let codeFile = options.test.codeFile {
            try await writeInvitations(service, count: options.test.invitations, to: codeFile)
            console.say("pairing codes written: \(options.test.invitations) (single use, not printed)")
        } else {
            await printInvitation(service, console, qr: options.qr)
        }
        if let readyFile = options.test.readyFile {
            let ready: [String: Any] = [
                "source_id": service.sourceID, "fingerprint": service.fingerprint, "port": service.port,
                "endpoints": service.endpoints.map { ["host": $0.host, "port": $0.port] },
                "roots": options.roots.map(\.path),
            ]
            try JSONSerialization.data(withJSONObject: ready, options: [.sortedKeys]).write(to: readyFile)
        }
        console.say("ready")

        if options.test.logRequests {
            Task {
                var printed = 0
                var connections = 0
                var decrypted = 0
                while !Task.isCancelled {
                    // Accepted TCP connections (cumulative): shows a client that connected but never completed TLS
                    // and sent a request, such as one waiting for its app to answer a trust challenge. Decrypted
                    // bytes (cumulative) stay 0 when every client refused this source's key in the handshake.
                    let accepted = service.connectionCount
                    let bytes = service.decryptedBytesReceived
                    if accepted != connections || bytes != decrypted {
                        console.say("connections \(RFC3339.formatMilliseconds(Date())) accepted=\(accepted) decrypted_bytes=\(bytes)")
                        connections = accepted
                        decrypted = bytes
                    }
                    let log = service.requestLog
                    for entry in log.dropFirst(printed) {
                        let fault = entry.fault.map { " fault=\($0)" } ?? ""
                        console.say("request \(RFC3339.formatMilliseconds(Date())) \(entry.method) \(entry.path) range=\(entry.range ?? "-") -> \(entry.status)\(fault)")
                    }
                    printed = log.count
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
        }

        if options.test.serveUntilKilled {
            // The scripts end this mode with SIGTERM: stop serving, then return (no leaked continuation).
            await Self.waitForTermination()
            await service.stop()
            console.say("stopped (SIGTERM)")
            return
        }

        for await line in console.lines() {
            let words = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let command = words.first else { continue }
            switch (command, words.count) {
            case ("invite", 1):
                await printInvitation(service, console, qr: options.qr)
            case ("items", 1):
                let page = try await service.library.catalog(after: nil, limit: TransferProtocol.maximumPageLimit)
                for item in page.items {
                    console.say("item \(item.itemID) \(item.preparationState.rawValue) \(item.kind.rawValue) \(item.totalBytes) \(item.title)")
                }
                console.say("end")
            case ("devices", 1):
                for device in await service.pairing.pairedDevices() {
                    console.say("device \(device.deviceID) \(device.isActive ? "active" : "revoked") \(device.deviceName)")
                }
                console.say("end")
            case ("send", 3):
                do {
                    guard CanonicalID.isValid(words[1]), CanonicalID.isValid(words[2]) else { throw CommandError.invalidID }
                    guard await service.pairing.pairedDevices().contains(where: { $0.deviceID == words[2] && $0.isActive }) else {
                        throw CommandError.unknownDevice
                    }
                    console.say("preparing transfer")
                    let entry = try await service.send(itemID: words[1], toDevice: words[2])
                    console.say("queued \(entry.queueEntryID) version \(entry.itemVersionID ?? "-") state \(entry.state.rawValue)")
                } catch {
                    console.say("error: \(error)")
                }
            case ("queue", 1):
                for entry in await service.queue.entries() {
                    let failure = entry.lastFailure.map { " failure=\($0.code)" } ?? ""
                    console.say("entry \(entry.queueEntryID) device \(entry.deviceID) item \(entry.itemID) state \(entry.state.rawValue)\(failure)")
                }
                console.say("end")
            case ("revoke", 2):
                do {
                    let revoked = try await service.revoke(deviceID: words[1])
                    console.say(revoked ? "revoked \(words[1])" : "no active device \(words[1])")
                } catch {
                    console.say("error: \(error)")
                }
            case ("quit", 1):
                await service.stop()
                console.say("stopped")
                return
            default:
                console.say("unknown command; see --help")
            }
        }
        await service.stop()
    }

    /// Returns when the process receives SIGTERM (whose default action, ending the process at once, is
    /// replaced by this wait).
    static func waitForTermination() async {
        signal(SIGTERM, SIG_IGN)
        let signals = AsyncStream<Void> { continuation in
            let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
            source.setEventHandler { continuation.yield() }
            continuation.onTermination = { _ in source.cancel() }
            source.resume()
        }
        for await _ in signals { return }
    }

    /// Test mode: codes go to a file only this user can read; the secret never reaches stdout or a log.
    static func writeInvitations(_ service: SourceService, count: Int, to url: URL) async throws {
        var lines: [String] = []
        for _ in 0..<count { lines.append(try await service.issueInvitation().code()) }
        FileManager.default.createFile(
            atPath: url.path, contents: Data((lines.joined(separator: "\n") + "\n").utf8), attributes: [.posixPermissions: 0o600])
    }

    static func printInvitation(_ service: SourceService, _ console: Console, qr: Bool) async {
        let payload = await service.issueInvitation()
        do {
            let link = try payload.link()
            console.say("pairing code: \(try payload.code())")
            console.say("pairing link: \(link)")
            console.say("invitation expires: \(RFC3339.format(payload.expiresAt)) (single use)")
            if qr { drawQRCode(link, console) }
        } catch {
            console.say("error: could not encode the invitation")
        }
    }

    /// `--qr`: the pairing link as a QR code on the controlling terminal only. It holds the invitation secret,
    /// so it never goes to standard output, which may be redirected into a file or a log.
    static func drawQRCode(_ link: String, _ console: Console) {
        let lines: [String]
        let columns: Int
        do {
            lines = try PairingQRCode.terminalLines(for: link)
            columns = try PairingQRCode.columns(for: link)
        } catch {
            console.say("qr: not drawn (\(error)); paste the code instead")
            return
        }
        let text = "pairing QR code (the link above; scan it with the Sylvia app's own scanner, not the Camera app):\n"
            + lines.joined(separator: "\n") + "\n"
            + "the QR code needs \(columns) terminal columns; if it looks broken, widen the terminal and type invite for a new one\n"
        if console.writeToTerminal(text) {
            console.say("qr: drawn on the terminal only (not in this output)")
        } else {
            console.say("qr: not drawn: no controlling terminal (the QR code is never written to standard output)")
        }
    }

    enum CommandError: Error, CustomStringConvertible {
        case invalidID
        case unknownDevice
        var description: String {
            switch self {
            case .invalidID: "IDs are lowercase UUIDs"
            case .unknownDevice: "no active paired device with that ID"
            }
        }
    }
}

/// Command-line options.
struct Options {
    var roots: [URL] = []
    var state = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.jevidon.sylvia.spike.source", isDirectory: true)
    var bind: [String] = []
    var port = 0
    var advertisedHosts: [String] = []
    var name = Host.current().localizedName ?? "Mac"
    var bonjour = false
    var ephemeralIdentity = false
    var invitationMinutes = 10
    var partSizeMiB = 16
    var qr = false
    var test = TestOptions()

    struct ParseError: Error, CustomStringConvertible {
        let description: String
    }

    static func parse(_ arguments: [String], allowTestOptions: Bool) throws -> Options {
        var options = Options()
        var lan = false
        var index = 0
        func value() throws -> String {
            index += 1
            guard index < arguments.count else { throw ParseError(description: "\(arguments[index - 1]) needs a value") }
            return arguments[index]
        }
        while index < arguments.count {
            switch arguments[index] {
            case "--root": options.roots.append(URL(fileURLWithPath: try value(), isDirectory: true))
            case "--state": options.state = URL(fileURLWithPath: try value(), isDirectory: true)
            case "--bind": options.bind.append(try value())
            case "--lan": lan = true
            case "--port":
                guard let port = Int(try value()), (0...65_535).contains(port) else { throw ParseError(description: "invalid --port") }
                options.port = port
            case "--advertise-host":
                let host = try value()
                guard HostValidation.isValid(host) else { throw ParseError(description: "invalid --advertise-host") }
                options.advertisedHosts.append(host)
            case "--name": options.name = try value()
            case "--bonjour": options.bonjour = true
            case "--ephemeral-identity": options.ephemeralIdentity = true
            case "--invitation-minutes":
                guard let minutes = Int(try value()), (1...60).contains(minutes) else {
                    throw ParseError(description: "--invitation-minutes must be 1 to 60")
                }
                options.invitationMinutes = minutes
            case "--part-size-mib":
                guard let mib = Int(try value()), (1...64).contains(mib) else { throw ParseError(description: "--part-size-mib must be 1 to 64") }
                options.partSizeMiB = mib
            case "--qr": options.qr = true
            case "--help", "-h":
                print(SourceCommandLine.usage + (allowTestOptions ? SourceCommandLine.testUsage : ""))
                exit(0)
            case let option where allowTestOptions && option.hasPrefix("--test-"):
                try options.test.parse(option, value: value)
            default:
                throw ParseError(description: "unknown option \(arguments[index])")
            }
            index += 1
        }
        guard !options.roots.isEmpty else { throw ParseError(description: "at least one --root is required") }
        for root in options.roots {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw ParseError(description: "not a folder: \(root.path)")
            }
        }
        if options.bind.isEmpty { options.bind = ["127.0.0.1"] }
        if lan { options.bind += LANAddresses.ipv4() }
        options.name = String(options.name.unicodeScalars.filter { $0.properties.generalCategory != .control }.prefix(PairingPayload.maximumSourceNameLength).map(Character.init))
        if options.name.isEmpty { options.name = "Mac" }
        return options
    }
}

/// Test-only options of `sylvia-test-source`. `sylvia-source` refuses every one of them.
struct TestOptions {
    var autoApprove = false
    var codeFile: URL?
    var invitations = 1
    var readyFile: URL?
    var corruptParts: [Int] = []
    var throttleKiBPerSecond: Int?
    var closeConnections = false
    var serveUntilKilled = false
    var logRequests = false
    var sendOnPairTitle: String?

    var isActive: Bool {
        autoApprove || codeFile != nil || readyFile != nil || !corruptParts.isEmpty || throttleKiBPerSecond != nil
            || closeConnections || serveUntilKilled || logRequests || sendOnPairTitle != nil
    }

    var summary: String {
        var parts: [String] = []
        if autoApprove { parts.append("auto-approve") }
        if !corruptParts.isEmpty { parts.append("corrupt first response of parts \(corruptParts.map(String.init).joined(separator: ","))") }
        if let throttleKiBPerSecond { parts.append("throttle \(throttleKiBPerSecond) KiB/s") }
        if closeConnections { parts.append("Connection: close") }
        if codeFile != nil { parts.append("codes to file") }
        if sendOnPairTitle != nil { parts.append("queue an item for each paired device") }
        return parts.isEmpty ? "hooks only" : parts.joined(separator: ", ")
    }

    mutating func parse(_ option: String, value: () throws -> String) throws {
        switch option {
        case "--test-auto-approve": autoApprove = true
        case "--test-code-file": codeFile = URL(fileURLWithPath: try value())
        case "--test-invitations":
            guard let count = Int(try value()), (1...20).contains(count) else { throw Options.ParseError(description: "--test-invitations must be 1 to 20") }
            invitations = count
        case "--test-ready-file": readyFile = URL(fileURLWithPath: try value())
        case "--test-corrupt-part":
            guard let index = Int(try value()), index >= 0 else { throw Options.ParseError(description: "invalid --test-corrupt-part") }
            corruptParts.append(index)
        case "--test-throttle-kib":
            guard let rate = Int(try value()), rate > 0 else { throw Options.ParseError(description: "invalid --test-throttle-kib") }
            throttleKiBPerSecond = rate
        case "--test-close-connections": closeConnections = true
        case "--test-serve-until-killed": serveUntilKilled = true
        case "--test-log-requests": logRequests = true
        case "--test-send-on-pair": sendOnPairTitle = try value()
        default: throw Options.ParseError(description: "unknown option \(option)")
        }
    }

    /// Nil when no fault is requested, so the service runs exactly as sylvia-source.
    func makeFaultPlan(partSizeBytes: Int64) -> FaultPlan? {
        guard !corruptParts.isEmpty || throttleKiBPerSecond != nil || closeConnections else { return nil }
        let plan = FaultPlan()
        let offsets = Set(corruptParts.map { Int64($0) * partSizeBytes })
        if !offsets.isEmpty {
            plan.add { info in
                guard let range = info.range, offsets.contains(range.lowerBound), info.attempt == 1 else { return nil }
                return .corruptByte(at: min(4_096, range.upperBound - range.lowerBound))
            }
        }
        if let throttleKiBPerSecond {
            let bytesPerSecond = Double(throttleKiBPerSecond) * 1_024
            let lastSent = Mutex<[String: Int64]>([:])
            plan.bodyProgress.withLock {
                $0 = { assetID, start, sent in
                    let key = "\(assetID)@\(start)"
                    let delta = lastSent.withLock { table -> Int64 in
                        let previous = table[key] ?? 0
                        table[key] = sent
                        return max(0, sent - (sent < previous ? 0 : previous))
                    }
                    try? await Task.sleep(for: .seconds(Double(delta) / bytesPerSecond))
                }
            }
        }
        if closeConnections { plan.setCloseAfterEachResponse(true) }
        return plan
    }
}

extension RFC3339 {
    /// Request log timestamps with milliseconds (UTC), so the log can be lined up with the phone's events.
    static func formatMilliseconds(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: TimeZone(identifier: "UTC")!))
    }
}

/// Test mode: approves every pairing request and says so on the terminal.
final class AutoApprover: PairingApprover {
    let console: Console
    /// Test only (`--test-send-on-pair`): called with the device ID of each approved request.
    let afterApproval = Mutex<(@Sendable (String) -> Void)?>(nil)
    init(console: Console) { self.console = console }
    func approve(_ request: PairingApprovalRequest) async -> Bool {
        console.say("auto-approved pairing request from \"\(request.deviceName)\" (device \(request.deviceID), address \(request.remoteAddress))")
        afterApproval.withLock { $0 }?(request.deviceID)
        return true
    }
}

extension SourceCommandLine {
    /// `--test-send-on-pair`: once the approved device's record exists, queue the item titled `title` for it, as
    /// the `send` command does.
    static func sendOnPair(title: String, deviceID: String, _ service: SourceService, _ console: Console) {
        Task {
            for _ in 0..<100 {
                if await service.pairing.pairedDevices().contains(where: { $0.deviceID == deviceID && $0.isActive }) { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            do {
                let page = try await service.library.catalog(after: nil, limit: TransferProtocol.maximumPageLimit)
                guard let item = page.items.first(where: { $0.title == title }) else {
                    console.say("test send-on-pair: no item titled \(title)")
                    return
                }
                let entry = try await service.send(itemID: item.itemID, toDevice: deviceID)
                console.say("test send-on-pair: queued \(entry.queueEntryID) item \(item.itemID) for device \(deviceID) state \(entry.state.rawValue)")
            } catch {
                console.say("test send-on-pair: error \(error)")
            }
        }
    }
}

/// IPv4 addresses of active `en*` interfaces (Wi-Fi and Ethernet), for `--lan`.
enum LANAddresses {
    static func ipv4() -> [String] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var addresses: [String] = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0,
                String(cString: entry.pointee.ifa_name).hasPrefix("en")
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                addresses.append(String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
            }
        }
        return addresses
    }
}

/// Terminal I/O. One reader owns stdin: while a pairing approval is pending, the next line answers it;
/// otherwise lines are commands.
final class Console: PairingApprover {
    private struct State {
        var pendingApproval: CheckedContinuation<Bool, Never>?
    }

    private let state = Mutex(State())
    private let output = Mutex(())

    func say(_ line: String) {
        output.withLock { _ in
            FileHandle.standardOutput.write(Data((line + "\n").utf8))
        }
    }

    /// Writes to the controlling terminal (`/dev/tty`), bypassing standard output and any redirection of it.
    /// False when the process has no controlling terminal.
    func writeToTerminal(_ text: String) -> Bool {
        output.withLock { _ in
            let descriptor = open("/dev/tty", O_WRONLY | O_NOCTTY | O_CLOEXEC)
            guard descriptor >= 0 else { return false }
            defer { close(descriptor) }
            let bytes = Array(text.utf8)
            var written = 0
            while written < bytes.count {
                let result = bytes[written...].withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
                if result < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                written += result
            }
            return true
        }
    }

    /// Lines from stdin that are not answers to an approval prompt. Ends at end of input.
    func lines() -> AsyncStream<String> {
        let (stream, continuation) = AsyncStream<String>.makeStream()
        let thread = Thread { [self] in
            while let line = readLine(strippingNewline: true) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let approval = state.withLock { state -> CheckedContinuation<Bool, Never>? in
                    defer { state.pendingApproval = nil }
                    return state.pendingApproval
                }
                if let approval {
                    approval.resume(returning: ["y", "yes"].contains(trimmed.lowercased()))
                } else {
                    continuation.yield(trimmed)
                }
            }
            continuation.finish()
        }
        thread.start()
        return stream
    }

    func approve(_ request: PairingApprovalRequest) async -> Bool {
        let approved = await withTaskCancellationHandler {
            await prompt(request)
        } onCancel: {
            // The Mac's approval timeout passed: withdraw the prompt so the next line is a command again.
            let pending = state.withLock { state -> CheckedContinuation<Bool, Never>? in
                defer { state.pendingApproval = nil }
                return state.pendingApproval
            }
            pending?.resume(returning: false)
        }
        say(approved ? "approved \(request.deviceID)" : "declined or timed out \(request.deviceID)")
        return approved
    }

    private func prompt(_ request: PairingApprovalRequest) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            // Checked under the lock the cancellation handler also takes: if the timeout already fired, the
            // prompt is never shown, so no later line can be mistaken for an answer.
            let refused = state.withLock { state -> Bool in
                if state.pendingApproval != nil || Task.isCancelled { return true }
                state.pendingApproval = continuation
                return false
            }
            if refused {
                continuation.resume(returning: false)  // one prompt at a time; a second request is refused
                return
            }
            say("pairing request from \"\(request.deviceName)\" (device \(request.deviceID), address \(request.remoteAddress))")
            say("compare with the fingerprint shown on the phone: \(request.sourceFingerprint)")
            say("approve? [y/N]")
        }
    }
}
