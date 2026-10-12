import Foundation
import Synchronization
import Testing
import SylviaTransferClient
import SylviaTransferCore

/// What App Transport Security does to the transfer client's connections (plan 14.3, ADR-0008), on the
/// simulator. Runs in the harness (no NSAppTransportSecurity key) and in the ATS probe variants
/// (Config/ATSVariant-*.plist, G02TransferATSVariant); the Info.plist key `G02ATSVariant` names the variant.
///
/// For each address form, three requests to the MAIN source or a control server on the same address:
/// 1. pinned HTTPS in an ephemeral (foreground) session: GET /v1/capabilities, trust answered only by
///    `PinnedTrustEvaluator.answer` with the source's SPKI pin;
/// 2. the same as a download task in a background session (nsurlsessiond);
/// 3. cleartext HTTP to a plain server on the same address, as a control for whether ATS treats the form as
///    exempt local networking.
/// Each records the HTTP status or the error (domain, code, underlying code) and whether a server-trust
/// challenge reached the delegate at all.
@Suite("Simulator: App Transport Security probe (14.3)", .serialized, .enabled(if: SimEnvironment.isConfigured, "run by simulator-background-run.sh"))
struct ATSProbeTests {
    struct Form: Sendable {
        var label: String
        var host: String
        var tailnet: Bool
    }

    static var variant: String { Bundle.main.object(forInfoDictionaryKey: "G02ATSVariant") as? String ?? "none" }

    static func forms() -> [Form] {
        let env = SimEnvironment.values
        var forms = [Form(label: "IPv4 loopback", host: "127.0.0.1", tailnet: false), Form(label: "IPv6 loopback", host: "::1", tailnet: false),
                     Form(label: "unqualified name", host: "localhost", tailnet: false)]
        if let value = env["G02_LAN_IP"], !value.isEmpty { forms.append(Form(label: "LAN IPv4", host: value, tailnet: false)) }
        if let value = env["G02_LOCAL_HOSTNAME"], !value.isEmpty { forms.append(Form(label: ".local name", host: value, tailnet: false)) }
        if let value = env["G02_TAILSCALE_IP"], !value.isEmpty { forms.append(Form(label: "Tailscale IPv4 (100.64/10)", host: value, tailnet: true)) }
        if let value = env["G02_MAGICDNS"], !value.isEmpty { forms.append(Form(label: "MagicDNS name (ts.net)", host: value, tailnet: true)) }
        return forms
    }

    struct Outcome: Sendable {
        var ok: Bool
        var text: String
        var challenges: [String]

        var summary: String { "\(text); challenges: \(challenges.isEmpty ? "none" : challenges.joined(separator: ","))" }
    }

    static func describe(_ error: any Error) -> String {
        let ns = error as NSError
        var text = "\(ns.domain) \(ns.code)"
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError { text += " (underlying \(underlying.domain) \(underlying.code))" }
        if let stream = ns.userInfo["_kCFStreamErrorCodeKey"] { text += " stream \(stream)" }
        return text
    }

    @Test func pinnedHTTPSAndCleartextByAddressForm() async throws {
        let info = try SimEnvironment.source("MAIN")
        let pin = try SPKIPin(hex: info.fingerprint.replacingOccurrences(of: " ", with: "").lowercased())
        let cleartextPath = try #require(SimEnvironment.values["G02_CLEARTEXT"])
        let cleartext = try JSONDecoder().decode([String: Int].self, from: Data(contentsOf: URL(fileURLWithPath: cleartextPath)))
        let ats = Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity")
        let variant = Self.variant
        if variant == "none" { #expect(ats == nil, "the harness itself must not declare any ATS key") }
        var lines = [
            "environment: simulator (\(ProcessInfo.processInfo.operatingSystemVersionString)), hosted test in \(Bundle.main.bundleIdentifier ?? "?")",
            "ATS variant: \(variant); Info.plist NSAppTransportSecurity: \(ats.map { "\($0)".replacingOccurrences(of: "\n", with: " ") } ?? "absent (ATS defaults)")",
            "pinned HTTPS = GET /v1/capabilities on the MAIN source (self-signed P-256 certificate whose name is not the host), trust answered only by the SPKI pin",
            "foreground = ephemeral URLSession data task; background = URLSessionConfiguration.background download task",
            "cleartext control = GET http://<host>:<port>/ on a plain Python server bound to the same address",
            "",
        ]
        let foreground = PinProbe(pin: pin, kind: .foreground)
        let background = PinProbe(pin: pin, kind: .background("com.jevidon.sylvia.spike.transfer.atsprobe.\(UUID().uuidString)"))
        defer { foreground.invalidate(); background.invalidate() }
        let plain = URLSession(configuration: .ephemeral)
        defer { plain.invalidateAndCancel() }
        var results: [(Form, Outcome, Outcome, String)] = []
        for form in Self.forms() {
            let endpoint = PairingPayload.Endpoint(host: form.host, port: info.port)
            let url = try #require(URL(string: "https://\(endpoint.urlHost):\(info.port)/v1/capabilities"))
            let fg = await foreground.fetch(url)
            let bg = await background.fetch(url)
            var clear = "no control server"
            if let port = cleartext[form.host], let plainURL = URL(string: "http://\(endpoint.urlHost):\(port)/") {
                do {
                    let (_, response) = try await plain.data(from: plainURL)
                    clear = "loaded (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))"
                } catch {
                    let ns = error as NSError
                    clear = (ns.code == NSURLErrorAppTransportSecurityRequiresSecureConnection ? "blocked by ATS: " : "failed: ") + Self.describe(error)
                }
            }
            results.append((form, fg, bg, clear))
            lines.append("\(form.label) [\(form.host)]")
            lines.append("  pinned HTTPS, foreground: \(fg.summary)")
            lines.append("  pinned HTTPS, background: \(bg.summary)")
            lines.append("  cleartext HTTP:           \(clear)")
        }
        if let directory = SimEnvironment.evidenceDirectory {
            try? FileManager.default.createDirectory(at: directory.appendingPathComponent("ats"), withIntermediateDirectories: true)
            try? Data((lines.joined(separator: "\n") + "\n").utf8).write(to: directory.appendingPathComponent("ats/ats-probe-\(variant).log"))
        }

        // Every local form (loopback, unqualified, LAN address, .local) must work pinned in both session kinds in
        // every configuration, including the harness with no ATS key at all.
        for (form, fg, bg, _) in results where !form.tailnet {
            #expect(fg.ok && bg.ok, "\(form.label): foreground \(fg.summary); background \(bg.summary)")
        }
        // Tailscale forms (observed 7 Oct 2026, iOS 26.5 simulator; this encodes it so a change is noticed):
        // - no ATS key, or only NSAllowsLocalNetworking: the trust challenge reaches the app and the pin matches,
        //   but the connection then fails with -1200 (stream -9802): ATS still requires default trust for these
        //   hosts, and a delegate cannot loosen it. Cleartext is blocked (-1022). Pinning alone cannot reach them.
        // - per-domain exception (ts.net, 100.64.0.0/10) with NSExceptionAllowsInsecureHTTPLoads: pinned HTTPS works
        //   in both session kinds, and cleartext HTTP to those hosts is allowed too (the cost of that key).
        for (form, fg, bg, clear) in results where form.tailnet {
            switch variant {
            case "none", "local-networking":
                #expect(!fg.ok && !bg.ok, "\(form.label) worked without a per-domain ATS exception")
                #expect(fg.text.contains("-1200") && bg.text.contains("-1200"), "\(form.label): \(fg.text) / \(bg.text)")
                #expect(fg.challenges == ["server_trust=matched"], "\(form.label): \(fg.challenges)")
                #expect(clear.hasPrefix("blocked by ATS"), "\(form.label) cleartext: \(clear)")
            case "tailnet-exception":
                #expect(fg.ok && bg.ok, "\(form.label): foreground \(fg.summary); background \(bg.summary)")
                #expect(fg.challenges == ["server_trust=matched"], "\(form.label): \(fg.challenges)")
                #expect(clear.hasPrefix("loaded"), "\(form.label) cleartext: \(clear)")
            default:
                Issue.record("unknown ATS variant \(variant)")
            }
        }
    }
}

/// A session whose only trust decision is the shared pinned answer, recording every challenge it sees.
final class PinProbe: NSObject, URLSessionDownloadDelegate, URLSessionDataDelegate, Sendable {
    enum Kind: Sendable {
        case foreground
        case background(String)
    }

    struct Pending {
        var continuation: CheckedContinuation<ATSProbeTests.Outcome, Never>?
        var challenges: [String] = []
        var status: Int?
    }

    let pin: SPKIPin
    private let state = Mutex<[Int: Pending]>([:])
    private let sessionBox = Mutex<URLSession?>(nil)

    init(pin: SPKIPin, kind: Kind) {
        self.pin = pin
        super.init()
        let configuration: URLSessionConfiguration
        switch kind {
        case .foreground: configuration = .ephemeral
        case .background(let identifier):
            configuration = .background(withIdentifier: identifier)
            configuration.isDiscretionary = false
        }
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        sessionBox.withLock { $0 = session }
    }

    func invalidate() { sessionBox.withLock { $0 }?.invalidateAndCancel() }

    func fetch(_ url: URL) async -> ATSProbeTests.Outcome {
        guard let session = sessionBox.withLock({ $0 }) else { return .init(ok: false, text: "no session", challenges: []) }
        let task: URLSessionTask = session.configuration.identifier == nil ? session.dataTask(with: url) : session.downloadTask(with: url)
        return await withCheckedContinuation { continuation in
            state.withLock { $0[task.taskIdentifier] = Pending(continuation: continuation) }
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let answer = PinnedTrustEvaluator.answer(challenge, acceptedPins: [pin])
        let method = challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust ? "server_trust" : challenge.protectionSpace.authenticationMethod
        state.withLock { $0[task.taskIdentifier]?.challenges.append("\(method)=\(answer.result.map { "\($0)" } ?? "default")") }
        completionHandler(answer.disposition, answer.credential)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode
        state.withLock { $0[downloadTask.taskIdentifier]?.status = status }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let pending = state.withLock { $0.removeValue(forKey: task.taskIdentifier) }
        guard let pending, let continuation = pending.continuation else { return }
        let status = pending.status ?? (task.response as? HTTPURLResponse)?.statusCode
        if let error {
            continuation.resume(returning: .init(ok: false, text: "error " + ATSProbeTests.describe(error), challenges: pending.challenges))
        } else {
            continuation.resume(returning: .init(ok: status == 200, text: "HTTP \(status.map(String.init) ?? "?")", challenges: pending.challenges))
        }
    }
}
